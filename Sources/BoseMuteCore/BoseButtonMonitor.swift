import Foundation

/// Detects the Bose QC Ultra 2 "Shortcut" when it is configured as voice control.
///
/// Diagnosis (see docs/DIAGNOSTICO.md): the gesture is not a HID key or an AVRCP media command.
/// The headset sends the HFP voice-recognition activation (AT+BVRA) to the Mac; bluetoothd owns
/// that HFP connection and hands it to Siri. There is no public API to receive or intercept it,
/// so this monitor *observes* the bluetoothd unified-log line that records the event:
///
///   [com.apple.bluetooth:Server.Handsfree] Received voice recognition event from device AA:BB:CC:11:22:33
///
/// Limitations: log text is not a stable API and may change with macOS updates; the event is
/// still delivered to Siri (not intercepted); any HFP headset sending BVRA matches unless an
/// address filter is set.
public final class BoseButtonMonitor {
    /// bluetoothd logs two lines per press ("Received voice recognition event…" and
    /// "Received 'start voice command' event…"). Only the first one counts, so a single press can
    /// never toggle twice even if processing the first one is slow.
    public static let markers = [
        "Received voice recognition event from device",
    ]
    /// Also streams the HFP call/SCO state lines so the menu can explain why a press may not arrive
    /// (e.g. the headset does not offer voice control while a call/SCO link is up).
    public static let predicate =
        "process == \"bluetoothd\" AND category == \"Server.Handsfree\" AND " +
        "(composedMessage CONTAINS[c] \"voice\" OR composedMessage CONTAINS \"call status\" OR " +
        "composedMessage CONTAINS \"Sco route\")"

    public enum State: Equatable {
        case stopped
        case running
        case failed(String)
    }

    public private(set) var state: State = .stopped
    public private(set) var lastEvent: (date: Date, address: String)?
    /// Uppercased Bluetooth address; nil accepts any device.
    public var addressFilter: String?
    public var debounce: TimeInterval = 1.5
    public var onPress: ((String) -> Void)?
    public var onStateChange: ((State) -> Void)?
    /// Other HFP lines (call status, SCO) for the diagnostic log.
    public var onDiagnostic: ((String) -> Void)?

    private var process: Process?
    private var buffer = Data()
    private var lastAccepted = Date.distantPast
    private var shouldRun = false

    public init() {}

    public func start() {
        shouldRun = true
        launch()
    }

    public func stop() {
        shouldRun = false
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        setState(.stopped)
    }

    private func launch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        p.arguments = ["stream", "--style", "ndjson", "--level", "default", "--predicate", Self.predicate]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            // Timestamp on arrival, not after the main queue finishes earlier work (a toggle can
            // block for a moment while drivers are verified).
            let arrival = Date()
            DispatchQueue.main.async { self?.consume(data, at: arrival) }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self, self.shouldRun else { return }
                self.setState(.failed("log stream terminou (status \(proc.terminationStatus)); reiniciando"))
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { if self.shouldRun { self.launch() } }
            }
        }
        do {
            try p.run()
            process = p
            setState(.running)
        } catch {
            setState(.failed("não foi possível iniciar /usr/bin/log: \(error.localizedDescription)"))
        }
    }

    private func setState(_ s: State) {
        state = s
        onStateChange?(s)
    }

    private func consume(_ data: Data, at arrival: Date) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let text = String(data: line, encoding: .utf8) else { continue }
            if let address = Self.parse(line: text) {
                handle(address: address, at: arrival)
            } else if let message = Self.eventMessage(text) {
                onDiagnostic?(message)
            }
        }
    }

    /// Exposed for tests: decides whether an event at `date` from `address` fires.
    @discardableResult
    public func handle(address: String, at date: Date) -> Bool {
        if let filter = addressFilter, filter.uppercased() != address.uppercased() { return false }
        guard date.timeIntervalSince(lastAccepted) >= debounce else { return false }
        lastAccepted = date
        lastEvent = (date, address)
        onPress?(address)
        return true
    }

    static func eventMessage(_ line: String) -> String? {
        guard line.hasPrefix("{"), let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["eventMessage"] as? String
    }

    /// Extracts the Bluetooth address from one ndjson (or compact) log line, or nil if it is not the event.
    /// Strict on purpose: `log stream` prints a "Filtering the log data using …" header that contains
    /// the marker text itself, so a line only counts when a full Bluetooth address follows the marker.
    public static func parse(line: String) -> String? {
        var message = line
        if line.hasPrefix("{") {
            guard let m = eventMessage(line) else { return nil }
            message = m
        } else if line.hasPrefix("Filtering the log data") {
            return nil
        }
        for marker in markers {
            guard let range = message.range(of: marker + " ") else { continue }
            let rest = message[range.upperBound...]
            guard let match = rest.range(of: #"^[0-9A-Fa-f]{2}([:-][0-9A-Fa-f]{2}){5}\b"#, options: .regularExpression) else {
                return nil
            }
            return rest[match].uppercased().replacingOccurrences(of: "-", with: ":")
        }
        return nil
    }
}
