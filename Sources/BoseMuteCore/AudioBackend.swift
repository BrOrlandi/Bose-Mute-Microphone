import Foundation

/// An input-capable audio device as seen by Core Audio.
public struct AudioInputDevice: Equatable, Sendable {
    public var id: UInt32
    public var uid: String
    public var name: String
    /// Four-character transport code, e.g. "blue" (Bluetooth), "bltn" (built-in), "virt" (virtual).
    public var transport: String
    /// True when any process on the system is doing I/O on the device.
    public var isRunningSomewhere: Bool
    public var isDefaultInput: Bool

    public init(id: UInt32, uid: String, name: String, transport: String,
                isRunningSomewhere: Bool = false, isDefaultInput: Bool = false) {
        self.id = id
        self.uid = uid
        self.name = name
        self.transport = transport
        self.isRunningSomewhere = isRunningSomewhere
        self.isDefaultInput = isDefaultInput
    }
}

/// Which input controls the driver exposes as writable.
public struct InputControlSupport: Equatable, Sendable {
    public var muteSettable: Bool
    /// Elements (0 = main, 1...n = channels) whose input volume is settable.
    public var settableVolumeElements: [UInt32]

    public init(muteSettable: Bool, settableVolumeElements: [UInt32]) {
        self.muteSettable = muteSettable
        self.settableVolumeElements = settableVolumeElements
    }
}

/// Input mute/volume values as read back from the driver.
public struct InputControlState: Codable, Equatable, Sendable {
    public var mute: Bool?
    public var volumes: [UInt32: Float]

    public init(mute: Bool?, volumes: [UInt32: Float]) {
        self.mute = mute
        self.volumes = volumes
    }
}

public struct AudioBackendError: Error, CustomStringConvertible, Equatable {
    public var description: String
    public init(_ description: String) { self.description = description }
}

/// Abstraction over Core Audio so the mute logic can be tested without touching real devices.
public protocol AudioInputBackend: AnyObject {
    func inputDevices() -> [AudioInputDevice]
    func support(for device: AudioInputDevice) -> InputControlSupport
    func readState(of device: AudioInputDevice) -> InputControlState
    func setMute(_ muted: Bool, on device: AudioInputDevice) throws
    func setVolume(_ value: Float, element: UInt32, on device: AudioInputDevice) throws
}
