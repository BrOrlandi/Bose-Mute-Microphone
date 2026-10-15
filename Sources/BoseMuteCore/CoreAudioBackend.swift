import CoreAudio
import Foundation

/// Real backend: uses only public Core Audio HAL properties
/// (kAudioDevicePropertyMute / kAudioDevicePropertyVolumeScalar, input scope).
public final class CoreAudioBackend: AudioInputBackend {
    private let system = AudioObjectID(kAudioObjectSystemObject)
    private var listenerQueue = DispatchQueue(label: "bose-mute.coreaudio.listeners")
    private var systemListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var deviceListeners: [AudioObjectID: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)]] = [:]
    private var onChange: (() -> Void)?

    public init() {}

    deinit { stopObserving() }

    // MARK: AudioInputBackend

    public func inputDevices() -> [AudioInputDevice] {
        let defaultInput: AudioObjectID = read(system, kAudioHardwarePropertyDefaultInputDevice) ?? 0
        return allDeviceIDs().compactMap { id in
            guard inputChannelCount(id) > 0 else { return nil }
            let uid: CFString? = readCF(id, kAudioDevicePropertyDeviceUID)
            let name: CFString? = readCF(id, kAudioObjectPropertyName)
            let transport: UInt32 = read(id, kAudioDevicePropertyTransportType) ?? 0
            let running: UInt32 = read(id, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0
            return AudioInputDevice(
                id: id,
                uid: (uid as String?) ?? "id-\(id)",
                name: (name as String?) ?? "Dispositivo \(id)",
                transport: fourCC(transport),
                isRunningSomewhere: running != 0,
                isDefaultInput: id == defaultInput
            )
        }
    }

    public func support(for device: AudioInputDevice) -> InputControlSupport {
        let id = AudioObjectID(device.id)
        let mute = isSettable(id, kAudioDevicePropertyMute, element: kAudioObjectPropertyElementMain)
        let elements = volumeElementCandidates(id).filter {
            isSettable(id, kAudioDevicePropertyVolumeScalar, element: $0)
        }
        return InputControlSupport(muteSettable: mute, settableVolumeElements: elements)
    }

    public func readState(of device: AudioInputDevice) -> InputControlState {
        let id = AudioObjectID(device.id)
        let mute: UInt32? = read(id, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeInput)
        var volumes: [UInt32: Float] = [:]
        for element in volumeElementCandidates(id) {
            if let v: Float32 = read(id, kAudioDevicePropertyVolumeScalar,
                                     scope: kAudioObjectPropertyScopeInput, element: element) {
                volumes[element] = v
            }
        }
        return InputControlState(mute: mute.map { $0 != 0 }, volumes: volumes)
    }

    public func setMute(_ muted: Bool, on device: AudioInputDevice) throws {
        try write(AudioObjectID(device.id), kAudioDevicePropertyMute, UInt32(muted ? 1 : 0),
                  element: kAudioObjectPropertyElementMain)
    }

    public func setVolume(_ value: Float, element: UInt32, on device: AudioInputDevice) throws {
        try write(AudioObjectID(device.id), kAudioDevicePropertyVolumeScalar, Float32(value), element: element)
    }

    // MARK: Change notifications

    /// Calls `handler` on the main queue (coalesced) whenever the device list, the default input,
    /// or any input mute/volume changes.
    public func startObserving(_ handler: @escaping () -> Void) {
        stopObserving()
        onChange = handler
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.refreshDeviceListeners()
                self?.notify()
            }
            if AudioObjectAddPropertyListenerBlock(system, &address, listenerQueue, block) == noErr {
                systemListeners.append((address, block))
            }
        }
        refreshDeviceListeners()
    }

    public func stopObserving() {
        for (address, block) in systemListeners {
            var a = address
            AudioObjectRemovePropertyListenerBlock(system, &a, listenerQueue, block)
        }
        systemListeners.removeAll()
        for (id, listeners) in deviceListeners {
            for (address, block) in listeners {
                var a = address
                AudioObjectRemovePropertyListenerBlock(id, &a, listenerQueue, block)
            }
        }
        deviceListeners.removeAll()
        onChange = nil
    }

    private var notifyPending = false
    private func notify() {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.notifyPending else { return }
            self.notifyPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.notifyPending = false
                self.onChange?()
            }
        }
    }

    private func refreshDeviceListeners() {
        let current = Set(inputDevices().map { AudioObjectID($0.id) })
        for (id, listeners) in deviceListeners where !current.contains(id) {
            for (address, block) in listeners {
                var a = address
                AudioObjectRemovePropertyListenerBlock(id, &a, listenerQueue, block)
            }
            deviceListeners[id] = nil
        }
        for id in current where deviceListeners[id] == nil {
            var registered: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
            let selectors: [(AudioObjectPropertySelector, AudioObjectPropertyScope)] = [
                (kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput),
                (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput),
                (kAudioDevicePropertyDeviceIsRunningSomewhere, kAudioObjectPropertyScopeGlobal),
            ]
            for (selector, scope) in selectors {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                         mElement: kAudioObjectPropertyElementWildcard)
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.notify() }
                if AudioObjectAddPropertyListenerBlock(id, &address, listenerQueue, block) == noErr {
                    registered.append((address, block))
                }
            }
            deviceListeners[id] = registered
        }
    }

    // MARK: HAL helpers

    private func allDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private func inputChannelCount(_ id: AudioObjectID) -> Int {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                                                 mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func volumeElementCandidates(_ id: AudioObjectID) -> [UInt32] {
        let channels = UInt32(min(inputChannelCount(id), 32))
        let elements = [kAudioObjectPropertyElementMain] + (channels > 0 ? Array(1...channels) : [])
        return elements.filter { hasProperty(id, kAudioDevicePropertyVolumeScalar, element: $0) }
    }

    private func hasProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                             element: UInt32) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: element)
        return AudioObjectHasProperty(id, &address)
    }

    private func isSettable(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, element: UInt32) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: element)
        guard AudioObjectHasProperty(id, &address) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &address, &settable) == noErr && settable.boolValue
    }

    private func read<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         element: UInt32 = kAudioObjectPropertyElementMain) -> T? where T: Numeric {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: T = 0
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func readCF(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> CFString? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue()
    }

    private func write<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ value: T,
                          element: UInt32) throws {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: element)
        guard AudioObjectHasProperty(id, &address) else {
            throw AudioBackendError("propriedade \(fourCC(selector)) inexistente")
        }
        var v = value
        let status = AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<T>.size), &v)
        guard status == noErr else {
            throw AudioBackendError("\(fourCC(selector)) elemento \(element): OSStatus \(status)")
        }
    }
}

func fourCC(_ code: UInt32) -> String {
    let bytes = withUnsafeBytes(of: code.bigEndian, Array.init)
    if bytes.allSatisfy({ $0 >= 32 && $0 < 127 }), let s = String(bytes: bytes, encoding: .ascii) { return s }
    return String(code)
}
