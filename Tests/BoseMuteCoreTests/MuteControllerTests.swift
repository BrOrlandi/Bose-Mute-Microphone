import XCTest
@testable import BoseMuteCore

final class FakeBackend: AudioInputBackend {
    struct Dev {
        var info: AudioInputDevice
        var support: InputControlSupport
        var state: InputControlState
        var rejectMute = false
        var muteIgnored = false
    }
    var devices: [String: Dev] = [:]
    var writes: [String] = []

    func add(_ uid: String, mute: Bool? = false, volumes: [UInt32: Float] = [0: 0.7],
             muteSettable: Bool = true, volumeSettable: Bool = true, running: Bool = false) {
        let id = UInt32(devices.count + 1)
        devices[uid] = Dev(
            info: AudioInputDevice(id: id, uid: uid, name: uid, transport: "test", isRunningSomewhere: running),
            support: InputControlSupport(muteSettable: muteSettable && mute != nil,
                                         settableVolumeElements: volumeSettable ? volumes.keys.sorted() : []),
            state: InputControlState(mute: mute, volumes: volumes))
    }

    func inputDevices() -> [AudioInputDevice] { devices.values.map(\.info).sorted { $0.uid < $1.uid } }
    func support(for d: AudioInputDevice) -> InputControlSupport { devices[d.uid]!.support }
    func readState(of d: AudioInputDevice) -> InputControlState { devices[d.uid]!.state }
    func setMute(_ m: Bool, on d: AudioInputDevice) throws {
        writes.append("\(d.uid).mute=\(m)")
        if devices[d.uid]!.rejectMute { throw AudioBackendError("rejected") }
        if devices[d.uid]!.muteIgnored { return }
        devices[d.uid]!.state.mute = m
    }
    func setVolume(_ v: Float, element: UInt32, on d: AudioInputDevice) throws {
        writes.append("\(d.uid).vol\(element)=\(v)")
        devices[d.uid]!.state.volumes[element] = v
    }
}

final class MuteControllerTests: XCTestCase {
    func testReleaseRestoresDeviceImmediately() {
        let b = FakeBackend()
        b.add("bose")
        b.add("usb")
        var ignored: Set<String> = []
        let c = MuteController(backend: FilteringBackend(base: b) { !ignored.contains($0.uid) })
        c.verifyTimeout = 0
        c.mute()
        ignored.insert("usb")
        XCTAssertNil(c.release(b.devices["usb"]!.info))
        XCTAssertEqual(b.devices["usb"]!.state.mute, false)
        XCTAssertEqual(c.status, .muted(verified: 1))
        c.unmute()
        XCTAssertTrue(c.lastRestoreIssues.isEmpty)
    }

    func testIgnoredDeviceIsNeitherTouchedNorCounted() {
        let b = FakeBackend()
        b.add("bose")
        b.add("teams", mute: false)
        b.devices["teams"]!.muteIgnored = true
        let c = MuteController(backend: FilteringBackend(base: b) { $0.uid != "teams" })
        c.verifyTimeout = 0
        XCTAssertEqual(c.toggle(), .muted(verified: 1))
        XCTAssertFalse(b.writes.contains { $0.hasPrefix("teams") })
    }

    func testToggleMutesAllAndRestoresOriginalValues() {
        let b = FakeBackend()
        b.add("bose", mute: false, volumes: [0: 1.0])
        b.add("builtin", mute: true, volumes: [0: 0.54]) // already muted by the user before
        let c = MuteController(backend: b)
        c.verifyTimeout = 0

        XCTAssertEqual(c.toggle(), .muted(verified: 2))
        XCTAssertEqual(b.devices["bose"]!.state.mute, true)
        XCTAssertEqual(b.devices["builtin"]!.state.mute, true)
        XCTAssertEqual(b.devices["bose"]!.state.volumes[0], 1.0, "mute property preferred; volume untouched")

        XCTAssertEqual(c.toggle(), .unmuted)
        XCTAssertEqual(b.devices["bose"]!.state.mute, false)
        XCTAssertEqual(b.devices["builtin"]!.state.mute, true, "restores previous state, not blindly unmutes")
        XCTAssertTrue(c.lastRestoreIssues.isEmpty)
    }

    func testFallsBackToVolumeZeroAndRestoresEveryChannel() {
        let b = FakeBackend()
        b.add("usb", mute: nil, volumes: [1: 0.3, 2: 0.8])
        let c = MuteController(backend: b)
        c.verifyTimeout = 0
        c.mute()
        XCTAssertEqual(c.reports["usb"]?.outcome, .muted(.volumeZero))
        XCTAssertEqual(b.devices["usb"]!.state.volumes, [1: 0, 2: 0])
        c.unmute()
        XCTAssertEqual(b.devices["usb"]!.state.volumes, [1: 0.3, 2: 0.8])
    }

    func testUnsupportedDeviceIsReportedNotClaimedMuted() {
        let b = FakeBackend()
        b.add("bose")
        b.add("virtual", mute: nil, volumes: [:], muteSettable: false, volumeSettable: false)
        let c = MuteController(backend: b)
        c.verifyTimeout = 0
        c.mute()
        XCTAssertEqual(c.status, .partial(verified: 1, total: 2))
        guard case .unsupported = c.reports["virtual"]?.outcome else { return XCTFail("expected unsupported") }
        XCTAssertNil(c.snapshots["virtual"], "nothing written, nothing to restore")
    }

    func testMuteThatDoesNotReadBackFallsBackToVolume() {
        let b = FakeBackend()
        b.add("liar", mute: false, volumes: [0: 0.6])
        b.devices["liar"]!.muteIgnored = true
        let c = MuteController(backend: b)
        c.verifyTimeout = 0
        c.mute()
        XCTAssertEqual(c.reports["liar"]?.outcome, .muted(.volumeZero))
        c.unmute()
        XCTAssertEqual(b.devices["liar"]!.state.volumes[0], 0.6)
    }

    func testFailureWhenNothingVerifies() {
        let b = FakeBackend()
        b.add("broken", mute: false, volumes: [:], volumeSettable: false)
        b.devices["broken"]!.rejectMute = true
        let c = MuteController(backend: b)
        c.verifyTimeout = 0
        c.mute()
        guard case .failed = c.reports["broken"]?.outcome else { return XCTFail("expected failed") }
        XCTAssertEqual(c.status, .partial(verified: 0, total: 1))
    }

    func testNewDeviceWhileMutedIsMutedAndRestored() {
        let b = FakeBackend()
        b.add("bose")
        let c = MuteController(backend: b)
        c.verifyTimeout = 0
        c.mute()
        b.add("airpods", mute: false, volumes: [0: 0.9])
        c.enforce()
        XCTAssertEqual(b.devices["airpods"]!.state.mute, true)
        XCTAssertEqual(c.status, .muted(verified: 2))
        c.unmute()
        XCTAssertEqual(b.devices["airpods"]!.state.mute, false)
    }

    func testExternalUnmuteWhileMutedIsReapplied() {
        let b = FakeBackend()
        b.add("bose")
        let c = MuteController(backend: b)
        c.verifyTimeout = 0
        c.mute()
        b.devices["bose"]!.state.mute = false // another app flipped it
        c.enforce()
        XCTAssertEqual(b.devices["bose"]!.state.mute, true)
        c.unmute()
        XCTAssertEqual(b.devices["bose"]!.state.mute, false, "original pre-mute value kept")
    }

    func testDeviceRemovedWhileMutedIsReportedOnRestore() {
        let b = FakeBackend()
        b.add("bose")
        b.add("usb")
        let c = MuteController(backend: b)
        c.verifyTimeout = 0
        c.mute()
        b.devices["usb"] = nil
        c.enforce()
        XCTAssertEqual(c.status, .muted(verified: 1))
        c.unmute()
        XCTAssertEqual(c.lastRestoreIssues.map(\.name), ["usb"])
    }

    func testDeviceReconnectedWhileMutedKeepsFirstOriginal() {
        let b = FakeBackend()
        b.add("bose", mute: false)
        let c = MuteController(backend: b)
        c.verifyTimeout = 0
        c.mute()
        // Driver re-creates the device unmuted (e.g. Bluetooth reconnect).
        b.devices["bose"]!.state.mute = false
        c.enforce()
        XCTAssertEqual(b.devices["bose"]!.state.mute, true)
        XCTAssertEqual(c.snapshots["bose"]?.original.mute, false)
    }

    func testResumeFromPersistedSnapshotsRestoresOnUnmute() {
        let b = FakeBackend()
        b.add("bose", mute: true) // still muted from a crashed run
        let saved = [DeviceSnapshot(uid: "bose", name: "bose",
                                    original: InputControlState(mute: false, volumes: [0: 0.7]), method: .muteProperty)]
        let c = MuteController(backend: b)
        c.verifyTimeout = 0
        c.resume(from: saved)
        XCTAssertTrue(c.isMuted)
        XCTAssertEqual(c.status, .muted(verified: 1))
        c.unmute()
        XCTAssertEqual(b.devices["bose"]!.state.mute, false)
    }

    func testMuteDoesNotWriteWhenAlreadyMuted() {
        let b = FakeBackend()
        b.add("bose")
        let c = MuteController(backend: b)
        c.verifyTimeout = 0
        c.mute()
        let writes = b.writes.count
        c.mute()
        XCTAssertEqual(b.writes.count, writes)
    }

    func testSnapshotsArePersistedAndCleared() {
        let b = FakeBackend()
        b.add("bose")
        let c = MuteController(backend: b)
        c.verifyTimeout = 0
        var persisted: [[DeviceSnapshot]] = []
        c.onSnapshotsChanged = { persisted.append($0) }
        c.mute()
        c.unmute()
        XCTAssertEqual(persisted.first?.count, 1)
        XCTAssertEqual(persisted.last?.count, 0)
    }

    func testSnapshotStoreRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let store = SnapshotStore(url: url)
        let s = [DeviceSnapshot(uid: "a", name: "A", original: InputControlState(mute: false, volumes: [0: 0.5, 2: 0.25]),
                                method: .volumeZero)]
        store.save(s)
        XCTAssertEqual(store.load(), s)
        store.save([])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}

final class BoseButtonMonitorTests: XCTestCase {
    func testParsesNdjsonLine() {
        let line = #"{"eventMessage":"Received voice recognition event from device AA:BB:CC:11:22:33","processImagePath":"/usr/sbin/bluetoothd"}"#
        XCTAssertEqual(BoseButtonMonitor.parse(line: line), "AA:BB:CC:11:22:33")
    }

    func testParsesCompactLineFromRealCapture() {
        let line = "2026-10-14 23:19:33.726 Df bluetoothd[408:3d57a9b] [com.apple.bluetooth:Server.Handsfree] Received voice recognition event from device AA:BB:CC:11:22:33"
        XCTAssertEqual(BoseButtonMonitor.parse(line: line), "AA:BB:CC:11:22:33")
    }

    func testIgnoresLogStreamHeaderThatContainsTheMarker() {
        // Regression: this header line caused a false toggle on first launch.
        let header = #"Filtering the log data using "process == "bluetoothd" AND composedMessage CONTAINS "Received voice recognition event from device"""#
        XCTAssertNil(BoseButtonMonitor.parse(line: header))
        XCTAssertNil(BoseButtonMonitor.parse(line: #"{"eventMessage":"Received voice recognition event from device <private>"}"#))
    }

    func testParsesStartVoiceCommandLine() {
        let line = #"{"eventMessage":"Received 'start voice command' event for device AA:BB:CC:11:22:33"}"#
        XCTAssertEqual(BoseButtonMonitor.parse(line: line), "AA:BB:CC:11:22:33")
        XCTAssertNil(BoseButtonMonitor.parse(line: #"{"eventMessage":"Received voice disconnection event for device AA:BB:CC:11:22:33"}"#))
    }

    func testIgnoresOtherLines() {
        XCTAssertNil(BoseButtonMonitor.parse(line: #"{"eventMessage":"Received Start Voice Command - Activating Siri"}"#))
        XCTAssertNil(BoseButtonMonitor.parse(line: "Filtering the log data using ..."))
    }

    func testDebounceAndAddressFilter() {
        let m = BoseButtonMonitor()
        var presses = 0
        m.onPress = { _ in presses += 1 }
        let t = Date()
        XCTAssertTrue(m.handle(address: "AA:BB:CC:11:22:33", at: t))
        XCTAssertFalse(m.handle(address: "AA:BB:CC:11:22:33", at: t.addingTimeInterval(0.3)), "duplicate log line")
        XCTAssertTrue(m.handle(address: "AA:BB:CC:11:22:33", at: t.addingTimeInterval(2)))
        m.addressFilter = "aa:bb:cc:11:22:33"
        XCTAssertFalse(m.handle(address: "40:5E:F6:D8:EA:30", at: t.addingTimeInterval(5)))
        XCTAssertTrue(m.handle(address: "AA:BB:CC:11:22:33", at: t.addingTimeInterval(5)))
        XCTAssertEqual(presses, 3)
    }

    func testToneWavHeader() {
        let wav = ToneGenerator.wav(ToneGenerator.muteCue)
        XCTAssertEqual(String(data: wav.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertGreaterThan(wav.count, 44 + 1000)
        XCTAssertNotEqual(ToneGenerator.wav(ToneGenerator.muteCue), ToneGenerator.wav(ToneGenerator.unmuteCue))
    }
}
