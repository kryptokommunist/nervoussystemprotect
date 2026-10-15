import Foundation
import CoreAudio
import AudioToolbox

/// Captures the system audio mix (everything other apps send to the speakers) using
/// Core Audio process taps (macOS 14.2+). No virtual driver like BlackHole required.
///
/// - Our own process is excluded from the tap, so our processed output is not re-captured.
/// - `muteBehavior = .mutedWhenTapped` silences the original audio at the speakers while we
///   are capturing it, so you only hear the processed version from nervoussystemprotect.
@available(macOS 14.2, *)
final class SystemAudioTap {
    typealias Handler = (_ left: UnsafePointer<Float>, _ right: UnsafePointer<Float>, _ frameCount: Int) -> Void

    enum TapError: LocalizedError {
        case ownProcessNotFound
        case createTap(OSStatus)
        case createAggregate(OSStatus)
        case createIOProc(OSStatus)
        case start(OSStatus)

        var errorDescription: String? {
            switch self {
            case .ownProcessNotFound: return "Could not identify own audio process for tap exclusion."
            case .createTap(let s): return "Could not create system audio tap (\(s)). Check System Settings › Privacy & Security › Screen & System Audio Recording."
            case .createAggregate(let s): return "Could not create tap aggregate device (\(s))."
            case .createIOProc(let s): return "Could not create tap IO proc (\(s))."
            case .start(let s): return "Could not start system audio capture (\(s))."
            }
        }
    }

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var tapFormat = AudioStreamBasicDescription()
    private let ioQueue = DispatchQueue(label: "com.nsp.systemtap.io", qos: .userInteractive)

    private static let scratchCapacity = 16384
    private let scratchL = UnsafeMutablePointer<Float>.allocate(capacity: SystemAudioTap.scratchCapacity)
    private let scratchR = UnsafeMutablePointer<Float>.allocate(capacity: SystemAudioTap.scratchCapacity)

    /// Sample rate the tap delivers audio at (valid after `prepare`).
    private(set) var sampleRate: Double = 48000

    deinit {
        stop()
        scratchL.deallocate()
        scratchR.deallocate()
    }

    /// Creates the tap + private aggregate device.
    /// `clockDeviceUID`: the device providing the clock (the output destination, e.g. headphones).
    /// `targetDeviceUID`: optional specific hardware device whose output stream to capture (e.g. BuiltInSpeakerDevice).
    func prepare(clockDeviceUID: String, targetDeviceUID: String? = nil) throws {
        stop()

        // 1. Exclude our own process so our processed output is not captured again.
        guard let ownProcess = Self.processObject(for: getpid()) else {
            throw TapError.ownProcessNotFound
        }

        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [ownProcess])
        if let targetUID = targetDeviceUID {
            desc.deviceUID = targetUID
        }
        desc.uuid = UUID()
        desc.name = "NSP System Tap"
        desc.isPrivate = true
        desc.muteBehavior = .mutedWhenTapped

        var newTap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(desc, &newTap)
        guard status == noErr, newTap != kAudioObjectUnknown else { throw TapError.createTap(status) }
        tapID = newTap

        // 2. Read tap stream format.
        var fmtAddr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var fmtSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        AudioObjectGetPropertyData(tapID, &fmtAddr, 0, nil, &fmtSize, &tapFormat)

        // 3. Private aggregate device that hosts the tap, clocked by the output device.
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "NSP System Tap Device",
            kAudioAggregateDeviceUIDKey: "com.nsp.systemtap.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: clockDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: clockDeviceUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: desc.uuid.uuidString
                ]
            ]
        ]
        var newAgg = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &newAgg)
        guard status == noErr, newAgg != kAudioObjectUnknown else {
            stop()
            throw TapError.createAggregate(status)
        }
        aggregateID = newAgg

        // Small IO buffer for low latency.
        var frames: UInt32 = 256
        var bufAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectSetPropertyData(aggregateID, &bufAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &frames)

        // Effective sample rate = aggregate nominal rate (tap is drift-compensated into it).
        var rate: Float64 = 0
        var rateSize = UInt32(MemoryLayout<Float64>.size)
        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectGetPropertyData(aggregateID, &rateAddr, 0, nil, &rateSize, &rate) == noErr, rate > 0 {
            sampleRate = rate
        } else if tapFormat.mSampleRate > 0 {
            sampleRate = tapFormat.mSampleRate
        }
    }

    /// Starts delivering captured audio to `handler` on a realtime IO thread.
    func start(handler: @escaping Handler) throws {
        guard aggregateID != kAudioObjectUnknown else { throw TapError.start(-1) }

        let scratchL = self.scratchL
        let scratchR = self.scratchR
        let capacity = Self.scratchCapacity

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue) { _, inInputData, _, _, _ in
            let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            let count = abl.count
            guard count > 0 else { return }

            let lastBuf = abl[count - 1]
            let channels = Int(lastBuf.mNumberChannels)

            if count >= 2 && channels == 1 {
                // Discrete non-interleaved channel buffers (e.g. built-in aggregate)
                let lBuf = abl[count - 2]
                let rBuf = abl[count - 1]
                guard let l = lBuf.mData?.assumingMemoryBound(to: Float.self),
                      let r = rBuf.mData?.assumingMemoryBound(to: Float.self) else { return }
                let frames = min(capacity, Int(lBuf.mDataByteSize) / MemoryLayout<Float>.size)
                handler(l, r, frames)
            } else if let data = lastBuf.mData?.assumingMemoryBound(to: Float.self) {
                // Interleaved buffer (e.g. Bluetooth headphones clocking the aggregate)
                let ch = max(1, channels)
                let frames = min(capacity, Int(lastBuf.mDataByteSize) / (MemoryLayout<Float>.size * ch))
                if ch == 1 {
                    handler(data, data, frames)
                } else {
                    for i in 0..<frames {
                        scratchL[i] = data[i * ch]
                        scratchR[i] = data[i * ch + 1]
                    }
                    handler(scratchL, scratchR, frames)
                }
            }
        }
        guard status == noErr, let procID else { throw TapError.createIOProc(status) }
        ioProcID = procID

        let startStatus = AudioDeviceStart(aggregateID, procID)
        guard startStatus == noErr else {
            stop()
            throw TapError.start(startStatus)
        }
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown {
            if let procID = ioProcID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
                ioProcID = nil
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
    }

    private static func processObject(for pid: pid_t) -> AudioObjectID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pidValue = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            UInt32(MemoryLayout<pid_t>.size),
            &pidValue,
            &size,
            &object
        )
        guard status == noErr, object != kAudioObjectUnknown else { return nil }
        return object
    }
}
