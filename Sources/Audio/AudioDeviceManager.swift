import Foundation
import CoreAudio
import AudioToolbox

public struct AudioDeviceInfo: Identifiable, Hashable {
    public let id: AudioDeviceID
    public let uid: String
    public let name: String
    public let isInput: Bool
    public let isOutput: Bool
    public let isBluetooth: Bool
    public let targetHardwareUID: String?

    public init(id: AudioDeviceID, uid: String, name: String, isInput: Bool, isOutput: Bool, isBluetooth: Bool = false, targetHardwareUID: String? = nil) {
        self.id = id
        self.uid = uid
        self.name = name
        self.isInput = isInput
        self.isOutput = isOutput
        self.isBluetooth = isBluetooth
        self.targetHardwareUID = targetHardwareUID
    }

    public init(id: AudioDeviceID, uid: String, name: String, isInput: Bool, isOutput: Bool) {
        self.init(id: id, uid: uid, name: name, isInput: isInput, isOutput: isOutput, isBluetooth: false, targetHardwareUID: nil)
    }

    public init(id: AudioDeviceID, uid: String, name: String, isInput: Bool, isOutput: Bool, targetHardwareUID: String?) {
        self.init(id: id, uid: uid, name: name, isInput: isInput, isOutput: isOutput, isBluetooth: false, targetHardwareUID: targetHardwareUID)
    }

    /// Pseudo input device: captures everything other apps play to the speakers (process tap).
    public static let systemAudioUID = "com.nsp.pseudo.systemaudio"
    public static let systemAudio = AudioDeviceInfo(
        id: AudioDeviceID(0xFFFF_FFF0),
        uid: systemAudioUID,
        name: "System Audio (all apps / default output)",
        isInput: true,
        isOutput: false,
        isBluetooth: false,
        targetHardwareUID: nil
    )

    public var isSystemAudio: Bool { uid.starts(with: "com.nsp.pseudo.") }
}

public final class AudioDeviceManager: ObservableObject {
    @Published public var inputDevices: [AudioDeviceInfo] = []
    @Published public var outputDevices: [AudioDeviceInfo] = []
    
    private var hardwareListenerBlock: AudioObjectPropertyListenerBlock?

    public init() {
        refreshDevices()
        setupHardwareListener()
    }

    deinit {
        removeHardwareListener()
    }

    public func refreshDevices() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize
        )

        guard status == noErr else {
            print("Failed to get audio devices data size: \(status)")
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        let getStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceIDs
        )

        guard getStatus == noErr else {
            print("Failed to get audio devices: \(getStatus)")
            return
        }

        var inputs: [AudioDeviceInfo] = []
        var outputs: [AudioDeviceInfo] = []

        if #available(macOS 14.2, *) {
            inputs.append(AudioDeviceInfo.systemAudio)
            // Explicitly support tapping audio routed to MacBook Pro Speakers
            inputs.append(AudioDeviceInfo(
                id: AudioDeviceID(0xFFFF_FFF1),
                uid: "com.nsp.pseudo.speakers",
                name: "MacBook Pro Speakers (Audio sent to Speakers)",
                isInput: true,
                isOutput: false,
                targetHardwareUID: "BuiltInSpeakerDevice"
            ))
        }

        for id in deviceIDs {
            guard let name = getDeviceName(id: id) else { continue }
            let uid = getDeviceUID(id: id) ?? "\(id)"

            // Filter out proprietary drivers that produce pure silence without their client running (Zoom)
            if uid.localizedCaseInsensitiveContains("zoomaudio") || name.localizedCaseInsensitiveContains("zoomaudio") {
                continue
            }

            // Filter out internal transient CoreAudio aggregates & NSP tap devices
            if uid.starts(with: "CADefaultDeviceAggregate") || name.starts(with: "CADefaultDeviceAggregate") {
                continue
            }
            if uid.starts(with: "com.nsp.systemtap") || name.localizedCaseInsensitiveContains("NSP System Tap") {
                continue
            }

            let hasInput = getChannelCount(id: id, isInput: true) > 0
            let hasOutput = getChannelCount(id: id, isInput: false) > 0

            var transAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var transType: UInt32 = 0
            var transSize = UInt32(MemoryLayout<UInt32>.size)
            let isBT = (AudioObjectGetPropertyData(id, &transAddr, 0, nil, &transSize, &transType) == noErr) &&
                       (transType == kAudioDeviceTransportTypeBluetooth || transType == kAudioDeviceTransportTypeBluetoothLE)

            let info = AudioDeviceInfo(id: id, uid: uid, name: name, isInput: hasInput, isOutput: hasOutput, isBluetooth: isBT)
            if hasInput { inputs.append(info) }
            if hasOutput { outputs.append(info) }
        }

        let applyUpdates = { [weak self] in
            guard let self = self else { return }
            if self.inputDevices != inputs {
                self.inputDevices = inputs
            }
            if self.outputDevices != outputs {
                self.outputDevices = outputs
            }
        }

        if Thread.isMainThread {
            applyUpdates()
        } else {
            DispatchQueue.main.async(execute: applyUpdates)
        }
    }

    public func getDefaultDevice(isInput: Bool) -> AudioDeviceInfo? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: isInput ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr, deviceID != 0 else { return nil }

        let list = isInput ? inputDevices : outputDevices
        return list.first(where: { $0.id == deviceID })
    }

    public func findBlackHoleDevice() -> AudioDeviceInfo? {
        return inputDevices.first { $0.name.localizedCaseInsensitiveContains("blackhole") }
    }

    /// Default source: System Audio tap (no driver needed) > BlackHole > system default input.
    public func preferredInputDevice() -> AudioDeviceInfo? {
        if let sys = inputDevices.first(where: { $0.isSystemAudio }) { return sys }
        if let bh = findBlackHoleDevice() { return bh }
        return getDefaultDevice(isInput: true)
    }

    /// Default microphone: Built-in Microphone or connected physical mic (excluding virtual devices)
    public func preferredMicrophone() -> AudioDeviceInfo? {
        if let mic = inputDevices.first(where: {
            !$0.isSystemAudio &&
            !$0.name.localizedCaseInsensitiveContains("blackhole") &&
            !$0.name.localizedCaseInsensitiveContains("teams") &&
            !$0.name.localizedCaseInsensitiveContains("zoom") &&
            ($0.uid == "BuiltInMicrophoneDevice" || $0.name.localizedCaseInsensitiveContains("microphone") || $0.name.localizedCaseInsensitiveContains("poly"))
        }) {
            return mic
        }
        return getDefaultDevice(isInput: true)
    }

    /// Default destination: Headphones/Headsets > Built-in Speakers > Non-virtual system default output.
    /// NEVER defaults to virtual sinks like BlackHole, Zoom, or Teams.
    public func preferredOutputDevice() -> AudioDeviceInfo? {
        // 1. Any connected headphones or headsets (Poly, AirPods, Bluetooth, etc.)
        if let hp = outputDevices.first(where: {
            let name = $0.name.lowercased()
            return name.contains("headphone") || name.contains("airpod") || name.contains("poly") || name.contains("buds") || name.contains("wh-")
        }) {
            return hp
        }
        // 2. Built-in Speakers
        if let spk = outputDevices.first(where: {
            $0.uid == "BuiltInSpeakerDevice" || $0.name.localizedCaseInsensitiveContains("speaker")
        }) {
            return spk
        }
        // 3. Fallback to system default if it's not a virtual loopback
        if let def = getDefaultDevice(isInput: false),
           !def.name.localizedCaseInsensitiveContains("blackhole"),
           !def.name.localizedCaseInsensitiveContains("zoom"),
           !def.name.localizedCaseInsensitiveContains("teams"),
           !def.name.localizedCaseInsensitiveContains("loopback") {
            return def
        }
        // 4. Any non-virtual output device
        return outputDevices.first(where: {
            !$0.name.localizedCaseInsensitiveContains("blackhole") &&
            !$0.name.localizedCaseInsensitiveContains("zoom") &&
            !$0.name.localizedCaseInsensitiveContains("teams") &&
            !$0.name.localizedCaseInsensitiveContains("loopback")
        }) ?? outputDevices.first
    }

    private func getDeviceName(id: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var unmanagedName: Unmanaged<CFString>? = nil
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = withUnsafeMutablePointer(to: &unmanagedName) { ptr in
            AudioObjectGetPropertyData(
                id,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                ptr
            )
        }

        guard status == noErr, let cfName = unmanagedName?.takeRetainedValue() else { return nil }
        return cfName as String
    }

    private func getDeviceUID(id: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var unmanagedUID: Unmanaged<CFString>? = nil
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        let status = withUnsafeMutablePointer(to: &unmanagedUID) { ptr in
            AudioObjectGetPropertyData(
                id,
                &propertyAddress,
                0,
                nil,
                &dataSize,
                ptr
            )
        }

        guard status == noErr, let cfUID = unmanagedUID?.takeRetainedValue() else { return nil }
        return cfUID as String
    }

    private func getChannelCount(id: AudioDeviceID, isInput: Bool) -> Int {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: isInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(id, &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return 0 }

        let bufferListPtr = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferListPtr.deallocate() }

        let getStatus = AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, bufferListPtr)
        guard getStatus == noErr else { return 0 }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPtr)
        var totalChannels = 0
        for buffer in bufferList {
            totalChannels += Int(buffer.mNumberChannels)
        }
        return totalChannels
    }

    private func setupHardwareListener() {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.refreshDevices()
        }
        self.hardwareListenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }

    private func removeHardwareListener() {
        guard let block = hardwareListenerBlock else { return }
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )
    }
}
