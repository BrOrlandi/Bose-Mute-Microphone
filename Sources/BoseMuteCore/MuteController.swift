import Foundation

/// How a device was silenced.
public enum MuteMethod: String, Codable, Sendable {
    /// kAudioDevicePropertyMute set to 1 and read back as 1.
    case muteProperty
    /// No usable mute control: every settable input volume set to 0 and read back as 0.
    case volumeZero
}

public enum DeviceOutcome: Equatable, Sendable {
    case muted(MuteMethod)
    case unsupported(String)
    case failed(String)

    public var isVerifiedMuted: Bool {
        if case .muted = self { return true }
        return false
    }
}

public struct DeviceReport: Equatable, Sendable {
    public var device: AudioInputDevice
    public var outcome: DeviceOutcome
}

/// What we changed on a device and the values to put back.
public struct DeviceSnapshot: Codable, Equatable, Sendable {
    public var uid: String
    public var name: String
    public var original: InputControlState
    public var method: MuteMethod?
}

public enum MuteStatus: Equatable, Sendable {
    case unmuted
    /// Every input device currently present is verified muted.
    case muted(verified: Int)
    /// Muted mode is on, but at least one present device is not verified muted.
    case partial(verified: Int, total: Int)
}

public struct RestoreIssue: Equatable, Sendable {
    public var name: String
    public var reason: String
}

/// Global input mute: silences every input device, keeps new devices silenced while active,
/// verifies the values the driver reports back, and restores the exact previous values.
public final class MuteController {
    public private(set) var isMuted = false
    public private(set) var reports: [String: DeviceReport] = [:]
    public private(set) var lastRestoreIssues: [RestoreIssue] = []
    public private(set) var snapshots: [String: DeviceSnapshot] = [:]

    private let backend: AudioInputBackend
    private let tolerance: Float = 0.001
    /// Some drivers apply writes asynchronously; read back for up to this long before giving up.
    public var verifyTimeout: TimeInterval = 0.3
    /// After unmute, keep checking restored devices for this long. Observed on the Bose QC Ultra 2:
    /// the Shortcut press that unmutes also starts Siri, which opens/closes an HFP (SCO) link, and
    /// the Bluetooth driver then reported mute = 1 again although the restore had been verified.
    public var restoreWatchDuration: TimeInterval = 20
    public var now: () -> Date = Date.init
    private var restoreWatch: (snapshots: [DeviceSnapshot], until: Date)?
    public private(set) var restoreReapplied: [String] = []

    /// True while restored values are still being watched (the app keeps its timer running).
    public var isWatchingRestore: Bool {
        guard let watch = restoreWatch else { return false }
        return now() < watch.until
    }
    /// Called whenever `snapshots` changes so they can be persisted (crash safety).
    public var onSnapshotsChanged: (([DeviceSnapshot]) -> Void)?

    public init(backend: AudioInputBackend) {
        self.backend = backend
    }

    public var status: MuteStatus {
        guard isMuted else { return .unmuted }
        let present = backend.inputDevices()
        let verified = present.filter { reports[$0.uid]?.outcome.isVerifiedMuted == true }.count
        return verified == present.count ? .muted(verified: verified) : .partial(verified: verified, total: present.count)
    }

    @discardableResult
    public func toggle() -> MuteStatus {
        isMuted ? unmute() : mute()
        return status
    }

    /// Resumes muted mode from snapshots persisted by a previous run that ended while muted.
    /// Only re-verifies; values are re-applied only where they drifted.
    public func resume(from saved: [DeviceSnapshot]) {
        guard !saved.isEmpty else { return }
        snapshots = Dictionary(saved.map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        isMuted = true
        enforce()
    }

    public func mute() {
        guard !isMuted else { enforce(); return }
        isMuted = true
        restoreWatch = nil
        lastRestoreIssues = []
        reports = [:]
        for device in backend.inputDevices() {
            apply(to: device)
        }
        onSnapshotsChanged?(Array(snapshots.values))
    }

    public func unmute() {
        guard isMuted else { return }
        isMuted = false
        var issues: [RestoreIssue] = []
        let present = Dictionary(backend.inputDevices().map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        for snapshot in snapshots.values.sorted(by: { $0.name < $1.name }) {
            guard let method = snapshot.method else { continue }
            guard let device = present[snapshot.uid] else {
                issues.append(RestoreIssue(name: snapshot.name, reason: "dispositivo ausente; estado anterior não pôde ser restaurado"))
                continue
            }
            if let reason = restore(snapshot, method: method, on: device) {
                issues.append(RestoreIssue(name: snapshot.name, reason: reason))
            }
        }
        restoreWatch = (Array(snapshots.values), now().addingTimeInterval(restoreWatchDuration))
        restoreReapplied = []
        snapshots = [:]
        reports = [:]
        lastRestoreIssues = issues
        onSnapshotsChanged?([])
    }

    /// Stops managing one device (e.g. the user chose to ignore it) and restores it right away if
    /// it was changed by us. Returns why the restore failed, if it did.
    @discardableResult
    public func release(_ device: AudioInputDevice) -> RestoreIssue? {
        reports[device.uid] = nil
        guard let snapshot = snapshots.removeValue(forKey: device.uid) else { return nil }
        onSnapshotsChanged?(Array(snapshots.values))
        guard let method = snapshot.method else { return nil }
        return restore(snapshot, method: method, on: device).map { RestoreIssue(name: snapshot.name, reason: $0) }
    }

    /// Re-checks every device while muted: mutes devices that appeared (or were re-plugged)
    /// and re-applies mute where something else changed it back.
    public func enforce() {
        guard isMuted else { enforceRestore(); return }
        let devices = backend.inputDevices()
        var changed = false
        for device in devices {
            if let snapshot = snapshots[device.uid], let method = snapshot.method {
                if isSilenced(backend.readState(of: device), method: method, device: device) {
                    reports[device.uid] = DeviceReport(device: device, outcome: .muted(method))
                    continue
                }
                // Drifted (or the device was re-created by the driver): mute again, keep the
                // original pre-mute values from the first snapshot.
                let outcome = silence(device, preferring: method)
                reports[device.uid] = DeviceReport(device: device, outcome: outcome)
                if case .muted(let newMethod) = outcome, newMethod != method {
                    snapshots[device.uid]?.method = newMethod
                    changed = true
                }
            } else if reports[device.uid] == nil {
                // New device (or one that came back) while muted.
                apply(to: device)
                changed = true
            }
        }
        let presentUIDs = Set(devices.map(\.uid))
        reports = reports.filter { presentUIDs.contains($0.key) }
        if changed { onSnapshotsChanged?(Array(snapshots.values)) }
    }

    /// While the restore watch is active, puts back any value the driver changed after unmute.
    private func enforceRestore() {
        guard let watch = restoreWatch else { return }
        guard now() < watch.until else { restoreWatch = nil; return }
        let present = Dictionary(backend.inputDevices().map { ($0.uid, $0) }, uniquingKeysWith: { a, _ in a })
        for snapshot in watch.snapshots {
            guard let method = snapshot.method, let device = present[snapshot.uid] else { continue }
            let state = backend.readState(of: device)
            let drifted: Bool
            switch method {
            case .muteProperty:
                drifted = state.mute != (snapshot.original.mute ?? false)
            case .volumeZero:
                drifted = snapshot.original.volumes.contains { key, value in
                    guard let actual = state.volumes[key] else { return false }
                    return abs(actual - value) > 0.01
                }
            }
            guard drifted else { continue }
            if let reason = restore(snapshot, method: method, on: device) {
                lastRestoreIssues.append(RestoreIssue(name: snapshot.name, reason: "re-restauração falhou: \(reason)"))
            }
            restoreReapplied.append(snapshot.name)
        }
    }

    // MARK: Private

    private func apply(to device: AudioInputDevice) {
        let original = backend.readState(of: device)
        snapshots[device.uid] = DeviceSnapshot(uid: device.uid, name: device.name, original: original, method: nil)
        let outcome = silence(device, preferring: nil)
        if case .muted(let method) = outcome {
            snapshots[device.uid]?.method = method
        } else if wroteSomething(device: device, original: original) {
            // Partial write (e.g. one channel accepted 0, another refused): restore by volume.
            snapshots[device.uid]?.method = .volumeZero
        } else {
            snapshots[device.uid] = nil
        }
        reports[device.uid] = DeviceReport(device: device, outcome: outcome)
    }

    private func silence(_ device: AudioInputDevice, preferring preferred: MuteMethod?) -> DeviceOutcome {
        let support = backend.support(for: device)
        var errors: [String] = []

        if support.muteSettable && preferred != .volumeZero {
            do {
                try backend.setMute(true, on: device)
                if verify({ backend.readState(of: device).mute == true }) { return .muted(.muteProperty) }
                errors.append("mute escrito mas leitura não confirmou")
            } catch {
                errors.append("mute: \(error)")
            }
        }

        if !support.settableVolumeElements.isEmpty {
            for element in support.settableVolumeElements {
                do { try backend.setVolume(0, element: element, on: device) } catch { errors.append("volume: \(error)") }
            }
            if verify({ isSilenced(backend.readState(of: device), method: .volumeZero, device: device) }) {
                return .muted(.volumeZero)
            }
            errors.append("volume 0 não confirmado na leitura")
        }

        if !support.muteSettable && support.settableVolumeElements.isEmpty {
            return .unsupported("driver não expõe mute nem volume de entrada graváveis")
        }
        return .failed(errors.joined(separator: "; "))
    }

    private func verify(_ check: () -> Bool) -> Bool {
        if check() { return true }
        let deadline = Date().addingTimeInterval(verifyTimeout)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
            if check() { return true }
        }
        return false
    }

    private func isSilenced(_ state: InputControlState, method: MuteMethod, device: AudioInputDevice) -> Bool {
        switch method {
        case .muteProperty:
            return state.mute == true
        case .volumeZero:
            let elements = backend.support(for: device).settableVolumeElements
            guard !elements.isEmpty else { return false }
            return elements.allSatisfy { (state.volumes[$0] ?? 1) <= tolerance }
        }
    }

    private func wroteSomething(device: AudioInputDevice, original: InputControlState) -> Bool {
        let now = backend.readState(of: device)
        if now.mute != original.mute { return true }
        return now.volumes.contains { key, value in abs((original.volumes[key] ?? value) - value) > tolerance }
    }

    /// Returns nil on success, otherwise why the restore could not be verified.
    private func restore(_ snapshot: DeviceSnapshot, method: MuteMethod, on device: AudioInputDevice) -> String? {
        var errors: [String] = []
        switch method {
        case .muteProperty:
            let expected = snapshot.original.mute ?? false
            do { try backend.setMute(expected, on: device) } catch { errors.append("mute: \(error)") }
            let actual = backend.readState(of: device).mute
            if actual != expected {
                errors.append("mute lido \(actual.map { "\($0)" } ?? "nil"), esperado \(expected)")
            }
        case .volumeZero:
            let elements = backend.support(for: device).settableVolumeElements
            for element in elements {
                guard let value = snapshot.original.volumes[element] else { continue }
                do { try backend.setVolume(value, element: element, on: device) } catch { errors.append("volume: \(error)") }
            }
            let now = backend.readState(of: device)
            for element in elements {
                guard let expected = snapshot.original.volumes[element], let actual = now.volumes[element] else { continue }
                if abs(expected - actual) > 0.01 {
                    errors.append("volume elemento \(element) lido \(actual), esperado \(expected)")
                }
            }
        }
        return errors.isEmpty ? nil : errors.joined(separator: "; ")
    }
}
