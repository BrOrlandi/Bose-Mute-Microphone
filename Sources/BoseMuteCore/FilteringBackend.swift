import Foundation

/// Hides devices from the mute logic (e.g. a virtual loopback the user chose to ignore,
/// or a single device during a self-test). All other calls pass through.
public final class FilteringBackend: AudioInputBackend {
    private let base: AudioInputBackend
    private let include: (AudioInputDevice) -> Bool

    public init(base: AudioInputBackend, include: @escaping (AudioInputDevice) -> Bool) {
        self.base = base
        self.include = include
    }

    public func inputDevices() -> [AudioInputDevice] { base.inputDevices().filter(include) }
    public func support(for d: AudioInputDevice) -> InputControlSupport { base.support(for: d) }
    public func readState(of d: AudioInputDevice) -> InputControlState { base.readState(of: d) }
    public func setMute(_ m: Bool, on d: AudioInputDevice) throws { try base.setMute(m, on: d) }
    public func setVolume(_ v: Float, element: UInt32, on d: AudioInputDevice) throws {
        try base.setVolume(v, element: element, on: d)
    }
}
