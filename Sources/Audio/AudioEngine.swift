import Foundation
import AVFoundation
import AudioToolbox
import Accelerate

/// Realtime pass-through DSP engine.
///
/// Routing design (low latency, works with virtual devices like BlackHole):
///   captureEngine: [input device] -> inputNode -> AVAudioSinkNode  --writes-->  ring buffer
///   engine:        ring buffer --reads--> AVAudioSourceNode -> DSP graph -> [output device]
///
/// The two engines run on their own device clocks. The ring buffer keeps a small, fixed
/// target latency and compensates for clock drift / sample-rate differences by reading with a
/// slightly adaptive resampling step, so latency can never accumulate.
///
/// NOTE: We intentionally do NOT use a CoreAudio aggregate device. Devices such as BlackHole
/// expose both input AND output channels, so in an aggregate their output channels come first
/// and our processed audio would be written straight back into BlackHole -> feedback loop /
/// massive "echo-like" delay.
public enum AffectPreset: String, CaseIterable, Identifiable {
    case natural = "NATURAL"
    case calmSoothe = "CALM SOOTHE"
    case deadpan = "DEADPAN"
    case robotDrone = "ROBOT DRONE"

    public var id: String { rawValue }
}

public final class AppAudioEngine: ObservableObject {
    private let engine = AVAudioEngine()          // DSP + playback (output device)
    private var captureEngine = AVAudioEngine()   // Realtime hardware capture
    private var sinkNode: AVAudioSinkNode?
    private var sourceNode: AVAudioSourceNode?
    private var systemTap: AnyObject?             // SystemAudioTap (macOS 14.2+) when source = System Audio
    private var inputDeviceID: AudioDeviceID = 0  // Hardware input device (e.g. MacBook Mic, BlackHole 2ch)
    private var inputIOProcID: AudioDeviceIOProcID?
    private let inputIOQueue = DispatchQueue(label: "com.nsp.input.io", qos: .userInteractive)
    private static let scratchCapacity = 16384
    private let inputScratchL = UnsafeMutablePointer<Float>.allocate(capacity: AppAudioEngine.scratchCapacity)
    private let inputScratchR = UnsafeMutablePointer<Float>.allocate(capacity: AppAudioEngine.scratchCapacity)
    private let pitchNode = AVAudioUnitTimePitch()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 2)
    private let dryMixer = AVAudioMixerNode()
    private let wetMixer = AVAudioMixerNode()
    private let outputMixer = AVAudioMixerNode()

    // MARK: - Affect De-escalator (Emotional Tone Neutralizer) Parameters
    @Published public var masterDamping: Float = 0.0 {
        didSet {
            guard !isApplyingPreset else { return }
            prosodyFlatten = masterDamping * 0.90
            syllableLeveler = masterDamping * 0.85
            urgencyNotchDb = -masterDamping * 14.0
            attackSoftener = masterDamping * 0.80
            breathGate = masterDamping * 0.70
            robotInharmonicity = (masterDamping > 0.80) ? (masterDamping - 0.80) * 2.2 : 0.0
            updateEQ()
            updatePitch()
        }
    }

    @Published public var prosodyFlatten: Float = 0.0 { didSet { updatePitch() } }
    @Published public var syllableLeveler: Float = 0.0
    @Published public var urgencyNotchDb: Float = 0.0 { didSet { updateEQ() } }
    @Published public var attackSoftener: Float = 0.0
    @Published public var breathGate: Float = 0.0
    @Published public var robotInharmonicity: Float = 0.0
    @Published public var isRobotDrone: Bool = false { didSet { updatePitch() } }
    @Published public var selectedAffectPreset: AffectPreset = .natural

    // Realtime modification metrics reported to UI
    @Published public var currentGainReductionDb: Float = 0.0
    @Published public var transientDampedActivity: Float = 0.0
    @Published public var breathGatedActive: Bool = false
    @Published public var inputPitchHz: Float = 0.0
    @Published public var outputPitchHz: Float = 0.0
    @Published public var pitchInflectionCents: Float = 0.0
    @Published public var flattenedInflectionCents: Float = 0.0
    @Published public var urgencyBandEnergyReduction: Float = 0.0

    private var isApplyingPreset: Bool = false
    private var dynamicProsodyCorrectionCents: Float = 0.0

    // DSP state for affect flattening
    private var levelerEnv: Float = 0.0
    private var transientGain: Float = 1.0
    private var prevL: Float = 0.0
    private var prevR: Float = 0.0
    private var carrierPhase: Float = 0.0
    private var gateGain: Float = 1.0
    private var rawReductionDb: Float = 0.0
    private var transientActivityMeter: Float = 0.0
    private var breathGatedMeter: Bool = false

    // Ring buffer state (interleaved stereo, power-of-two frame capacity)
    private static let ringCapacityFrames = 1 << 15 // ~680 ms @ 48 kHz (headroom only, not latency)
    private static let ringMask = ringCapacityFrames - 1
    private let ring: UnsafeMutablePointer<Float>
    private var writeFrame: Int = 0          // monotonic, in input-rate frames
    private var readPos: Double = 0          // monotonic, fractional, in input-rate frames
    private var maxWriteChunk: Int = 0       // largest input IO buffer seen
    private var smoothedFill: Double = 0
    private var primed: Bool = false
    private var resampleStep: Double = 1.0   // inputRate / outputRate
    private var minTargetFrames: Double = 480
    private let bufferLock = os_unfair_lock_t.allocate(capacity: 1)

    /// Preferred hardware IO buffer size (frames) for both devices.
    private let preferredIOBufferFrames: UInt32 = 256

    @Published public var isRunning: Bool = false
    @Published public var isBypassed: Bool = false {
        didSet { updateBypass() }
    }
    
    // Pitch shift: -12.0 to +12.0 semitones
    @Published public var pitchSemitones: Float = 0.0 {
        didSet { updatePitch() }
    }
    
    // Fine pitch shift: -100 to +100 cents
    @Published public var pitchCents: Float = 0.0 {
        didSet { updatePitch() }
    }
    
    // Warmth / Low-pass filter: 1,000 Hz to 20,000 Hz
    @Published public var cutoffFrequency: Float = 20000.0 {
        didSet { updateEQ() }
    }
    
    // Dry / Wet mix: 0.0 (100% dry) to 1.0 (100% wet)
    @Published public var dryWetMix: Float = 1.0 {
        didSet { updateMix() }
    }
    
    // Master volume: 0.0 to 1.5
    @Published public var masterVolume: Float = 1.0 {
        didSet { engine.mainMixerNode.outputVolume = masterVolume }
    }

    // VU Meter levels (0.0 to 1.0)
    @Published public var leftLevel: Float = 0.0
    @Published public var rightLevel: Float = 0.0
    public private(set) var rawLeftRMS: Float = 0.0
    public private(set) var rawRightRMS: Float = 0.0

    public func getCurrentRMS() -> (left: Float, right: Float) {
        os_unfair_lock_lock(bufferLock)
        let l = rawLeftRMS
        let r = rawRightRMS
        os_unfair_lock_unlock(bufferLock)
        return (l, r)
    }

    @Published public var selectedInputDevice: AudioDeviceInfo?
    @Published public var selectedOutputDevice: AudioDeviceInfo?
    @Published public var errorMessage: String?

    private var meterTapInstalled: Bool = false
    public private(set) var isRestarting: Bool = false
    private var restartWorkItem: DispatchWorkItem?
    private var isConfiguringEngine: Bool = false
    private var configChangeObserver: NSObjectProtocol?
    private var monitoredOutputDeviceID: AudioDeviceID = 0
    private var outputDeviceFormatListener: AudioObjectPropertyListenerBlock?
    private var activeOutputSampleRate: Double = 0
    private var activeOutputChannels: AVAudioChannelCount = 0

    // Test hooks for deterministic Bluetooth HFP 1-channel & configuration change verification
    public var simulatedOutputChannelsForTesting: AVAudioChannelCount? = nil
    public var isEngineActuallyRunning: Bool { engine.isRunning }

    public func simulateBluetoothHFPConfigurationChangeForTesting() {
        simulatedOutputChannelsForTesting = 1
        engine.stop()
        os_unfair_lock_lock(bufferLock)
        rawLeftRMS = 0.0
        rawRightRMS = 0.0
        os_unfair_lock_unlock(bufferLock)
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: engine)
    }

    public init() {
        bufferLock.initialize(to: os_unfair_lock())
        ring = UnsafeMutablePointer<Float>.allocate(capacity: Self.ringCapacityFrames * 2)
        ring.initialize(repeating: 0, count: Self.ringCapacityFrames * 2)
        inputScratchL.initialize(repeating: 0, count: Self.scratchCapacity)
        inputScratchR.initialize(repeating: 0, count: Self.scratchCapacity)
        setupInitialGraph()
        setupConfigurationChangeObserver()
    }

    deinit {
        if let obs = configChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        removeOutputDeviceFormatListener()
        stop()
        ring.deallocate()
        inputScratchL.deallocate()
        inputScratchR.deallocate()
        bufferLock.deallocate()
    }

    private func setupConfigurationChangeObserver() {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            guard let self = self, !self.isConfiguringEngine else { return }
            let handleChange = { [weak self] in
                guard let self = self, !self.isConfiguringEngine else { return }
                guard (self.isRunning || self.isRestarting) && !self.userStopped else { return }
                let hwFmt = self.engine.outputNode.outputFormat(forBus: 0)
                let curChannels = self.simulatedOutputChannelsForTesting ?? max(1, min(2, hwFmt.channelCount))
                let curRate = hwFmt.sampleRate > 0 ? hwFmt.sampleRate : 48000.0
                if !self.engine.isRunning || curChannels != self.activeOutputChannels || abs(curRate - self.activeOutputSampleRate) > 1.0 {
                    self.restart()
                }
            }
            if Thread.isMainThread {
                handleChange()
            } else {
                DispatchQueue.main.async(execute: handleChange)
            }
        }
    }

    private func installOutputDeviceFormatListener(deviceID: AudioDeviceID) {
        removeOutputDeviceFormatListener()
        guard deviceID != 0 && deviceID != kAudioObjectUnknown else { return }
        monitoredOutputDeviceID = deviceID

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self = self, !self.isConfiguringEngine else { return }
            guard (self.isRunning || self.isRestarting) && !self.userStopped else { return }
            let hwFmt = self.engine.outputNode.outputFormat(forBus: 0)
            let curChannels = self.simulatedOutputChannelsForTesting ?? max(1, min(2, hwFmt.channelCount))
            let curRate = hwFmt.sampleRate > 0 ? hwFmt.sampleRate : 48000.0
            if !self.engine.isRunning || curChannels != self.activeOutputChannels || abs(curRate - self.activeOutputSampleRate) > 1.0 {
                self.restart()
            }
        }
        outputDeviceFormatListener = block

        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(deviceID, &rateAddr, DispatchQueue.main, block)
        AudioObjectAddPropertyListenerBlock(deviceID, &streamAddr, DispatchQueue.main, block)
    }

    private func removeOutputDeviceFormatListener() {
        guard monitoredOutputDeviceID != 0, let block = outputDeviceFormatListener else { return }
        var rateAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(monitoredOutputDeviceID, &rateAddr, DispatchQueue.main, block)
        AudioObjectRemovePropertyListenerBlock(monitoredOutputDeviceID, &streamAddr, DispatchQueue.main, block)
        monitoredOutputDeviceID = 0
        outputDeviceFormatListener = nil
    }

    private func setupInitialGraph() {
        engine.attach(pitchNode)
        engine.attach(eqNode)
        engine.attach(dryMixer)
        engine.attach(wetMixer)
        engine.attach(outputMixer)

        if eqNode.bands.count >= 2 {
            let band0 = eqNode.bands[0]
            band0.filterType = .lowPass
            band0.frequency = cutoffFrequency
            band0.bandwidth = 0.707
            band0.bypass = false

            let band1 = eqNode.bands[1]
            band1.filterType = .parametric
            band1.frequency = 3400.0
            band1.bandwidth = 1.5
            band1.gain = urgencyNotchDb
            band1.bypass = urgencyNotchDb >= -0.5
        }

        updatePitch()
        updateEQ()
        updateMix()
        outputMixer.outputVolume = masterVolume
        engine.mainMixerNode.outputVolume = masterVolume
    }

    public func applyAffectPreset(_ preset: AffectPreset) {
        isApplyingPreset = true
        selectedAffectPreset = preset
        switch preset {
        case .natural:
            masterDamping = 0.0
            prosodyFlatten = 0.0
            syllableLeveler = 0.0
            urgencyNotchDb = 0.0
            attackSoftener = 0.0
            breathGate = 0.0
            robotInharmonicity = 0.0
            isRobotDrone = false
        case .calmSoothe:
            masterDamping = 0.40
            prosodyFlatten = 0.30
            syllableLeveler = 0.40
            urgencyNotchDb = -6.0
            attackSoftener = 0.50
            breathGate = 0.30
            robotInharmonicity = 0.0
            isRobotDrone = false
        case .deadpan:
            masterDamping = 0.75
            prosodyFlatten = 0.75
            syllableLeveler = 0.80
            urgencyNotchDb = -12.0
            attackSoftener = 0.75
            breathGate = 0.65
            robotInharmonicity = 0.0
            isRobotDrone = false
        case .robotDrone:
            masterDamping = 1.0
            prosodyFlatten = 1.0
            syllableLeveler = 1.0
            urgencyNotchDb = -15.0
            attackSoftener = 0.90
            breathGate = 0.80
            robotInharmonicity = 0.45
            isRobotDrone = true
        }
        isApplyingPreset = false
        updateEQ()
        updatePitch()
    }

    public var userStopped: Bool = false

    public func setInputDevice(_ device: AudioDeviceInfo, autoStartIfReady: Bool = true) {
        selectedInputDevice = device
        userStopped = false
        if isRunning || isRestarting {
            restart()
        } else if autoStartIfReady && selectedOutputDevice != nil {
            start()
        }
    }

    public func setOutputDevice(_ device: AudioDeviceInfo, autoStartIfReady: Bool = true) {
        selectedOutputDevice = device
        userStopped = false
        if isRunning || isRestarting {
            restart()
        } else if autoStartIfReady && selectedInputDevice != nil {
            start()
        }
    }

    public func start() {
        userStopped = false
        guard !isRunning && !isRestarting else { return }
        errorMessage = nil

        guard let inDev = selectedInputDevice else {
            errorMessage = "Please select an audio input source."
            return
        }
        guard let outDev = selectedOutputDevice else {
            errorMessage = "Please select an audio output destination."
            return
        }

        isConfiguringEngine = true
        defer { isConfiguringEngine = false }

        do {
            // 1. Playback engine -> output device
            engine.stop()
            guard let outUnit = engine.outputNode.audioUnit else {
                errorMessage = "CoreAudio output unit unavailable."
                return
            }
            let liveOutID = Self.liveDeviceID(for: outDev.uid, fallbackID: outDev.id)
            guard setDevice(liveOutID, on: outUnit) else {
                errorMessage = "Could not open output device \(outDev.name)."
                return
            }
            let outHWFormat = engine.outputNode.outputFormat(forBus: 0)
            let outRate = outHWFormat.sampleRate > 0 ? outHWFormat.sampleRate : 48000.0
            guard let dspFormat = AVAudioFormat(standardFormatWithSampleRate: outRate, channels: 2) else {
                errorMessage = "Failed to create DSP audio format."
                return
            }

            // 2. Prepare capture source (System Audio tap or a real hardware/virtual input device)
            var inputRate: Double = 48000.0

            if inDev.isSystemAudio {
                guard #available(macOS 14.2, *) else {
                    errorMessage = "System Audio capture requires macOS 14.2 or newer."
                    return
                }
                let tap = SystemAudioTap()
                try tap.prepare(clockDeviceUID: outDev.uid, targetDeviceUID: inDev.targetHardwareUID)
                systemTap = tap
                inputRate = tap.sampleRate
            } else {
                // Direct CoreAudio input IOProc from inDev.id (e.g. mic, BlackHole 2ch, USB mic)
                let liveInID = Self.liveDeviceID(for: inDev.uid, fallbackID: inDev.id)
                var rateAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyNominalSampleRate,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                var rate: Float64 = 48000.0
                var rateSize = UInt32(MemoryLayout<Float64>.size)
                AudioObjectGetPropertyData(liveInID, &rateAddr, 0, nil, &rateSize, &rate)
                if rate > 0 { inputRate = rate }

                // Request small IO buffer size on hardware device
                var frames = preferredIOBufferFrames
                var bufAddr = AudioObjectPropertyAddress(
                    mSelector: kAudioDevicePropertyBufferFrameSize,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain
                )
                AudioObjectSetPropertyData(liveInID, &bufAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &frames)

                var procID: AudioDeviceIOProcID?
                let scratchL = self.inputScratchL
                let scratchR = self.inputScratchR
                let scratchCap = Self.scratchCapacity

                let status = AudioDeviceCreateIOProcIDWithBlock(&procID, liveInID, inputIOQueue) { [weak self] _, inInputData, _, _, _ in
                    guard let self = self else { return }
                    let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
                    guard abl.count > 0 else { return }

                    if abl.count > 1,
                       let b0 = abl[0].mData?.assumingMemoryBound(to: Float.self),
                       let b1 = abl[1].mData?.assumingMemoryBound(to: Float.self) {
                        let f = Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size
                        self.writeInput(left: b0, right: b1, frameCount: f)
                    } else if let b0 = abl[0].mData?.assumingMemoryBound(to: Float.self) {
                        let channels = max(1, Int(abl[0].mNumberChannels))
                        let totalFrames = Int(abl[0].mDataByteSize) / (MemoryLayout<Float>.size * channels)
                        if channels == 1 {
                            self.writeInput(left: b0, right: b0, frameCount: totalFrames)
                        } else {
                            let f = min(totalFrames, scratchCap)
                            for i in 0..<f {
                                scratchL[i] = b0[i * channels]
                                scratchR[i] = b0[i * channels + 1]
                            }
                            self.writeInput(left: scratchL, right: scratchR, frameCount: f)
                        }
                    }
                }
                guard status == noErr, let p = procID else {
                    errorMessage = "Failed to start capture on \(inDev.name) (error: \(status))"
                    return
                }
                self.inputDeviceID = inDev.id
                self.inputIOProcID = p
            }

            // 3. Reset ring buffer & latency controller
            os_unfair_lock_lock(bufferLock)
            ring.update(repeating: 0, count: Self.ringCapacityFrames * 2)
            writeFrame = 0
            readPos = 0
            maxWriteChunk = 0
            smoothedFill = 0
            primed = false
            resampleStep = inputRate / outRate
            minTargetFrames = inputRate * 0.010 // >= 10 ms safety cushion
            os_unfair_lock_unlock(bufferLock)

            // 4. Remove old nodes
            removeMeterTap()
            if let oldSource = sourceNode {
                engine.disconnectNodeOutput(oldSource)
                engine.detach(oldSource)
                sourceNode = nil
            }

            // 5. Playback: source node pulls from ring buffer with drift compensation
            let newSource = AVAudioSourceNode(format: dspFormat) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
                guard let self = self else { return noErr }
                let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
                guard abl.count >= 2,
                      let left = abl[0].mData?.assumingMemoryBound(to: Float.self),
                      let right = abl[1].mData?.assumingMemoryBound(to: Float.self) else {
                    return noErr
                }
                self.readOutput(left: left, right: right, frameCount: Int(frameCount))
                return noErr
            }
            self.sourceNode = newSource
            engine.attach(newSource)

            // 6. Connect DSP Graph
            // Source splits to DryMixer and PitchNode
            let dryPoint = AVAudioConnectionPoint(node: dryMixer, bus: 0)
            let pitchPoint = AVAudioConnectionPoint(node: pitchNode, bus: 0)
            engine.connect(newSource, to: [dryPoint, pitchPoint], fromBus: 0, format: dspFormat)

            // Wet Path: Pitch -> EQ -> WetMixer
            engine.connect(pitchNode, to: eqNode, format: dspFormat)
            engine.connect(eqNode, to: wetMixer, format: dspFormat)

            // Mixers -> OutputMixer -> MainMixer -> Output (re-link to the newly selected device format)
            let outChannels = simulatedOutputChannelsForTesting ?? max(1, min(2, outHWFormat.channelCount))
            let busFormat = AVAudioFormat(standardFormatWithSampleRate: outRate, channels: outChannels) ?? dspFormat
            activeOutputSampleRate = outRate
            activeOutputChannels = outChannels
            engine.connect(dryMixer, to: outputMixer, format: dspFormat)
            engine.connect(wetMixer, to: outputMixer, format: dspFormat)
            engine.connect(outputMixer, to: engine.mainMixerNode, format: busFormat)
            engine.connect(engine.mainMixerNode, to: engine.outputNode, format: outHWFormat)

            // 7. Install Meter Tap on Output Mixer (format: nil so both 1-ch Bluetooth HFP and 2-ch A2DP buses work)
            installMeterTap(format: nil)

            // 8. Start playback first (silence until the buffer is primed), then capture
            engine.prepare()
            try engine.start()
            if #available(macOS 14.2, *), let tap = systemTap as? SystemAudioTap {
                try tap.start { [weak self] l, r, frames in
                    self?.writeInput(left: l, right: r, frameCount: frames)
                }
            } else if let p = inputIOProcID {
                let status = AudioDeviceStart(inputDeviceID, p)
                if status != noErr {
                    print("Warning: AudioDeviceStart failed on input device: \(status)")
                }
            }
            installOutputDeviceFormatListener(deviceID: liveOutID)
            isRunning = true
            updateMix()
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            print("AudioEngine start error: \(error)")
            isRunning = true // ensure stop() performs full cleanup
            stop()
        }
    }

    public func stop(preserveRestarting: Bool = false) {
        if !preserveRestarting {
            restartWorkItem?.cancel()
            restartWorkItem = nil
            isRestarting = false
        }
        guard isRunning || engine.isRunning || systemTap != nil || inputIOProcID != nil else { return }
        removeOutputDeviceFormatListener()
        removeMeterTap()
        if #available(macOS 14.2, *), let tap = systemTap as? SystemAudioTap {
            tap.stop()
        }
        systemTap = nil
        if inputDeviceID != 0, let p = inputIOProcID {
            AudioDeviceStop(inputDeviceID, p)
            AudioDeviceDestroyIOProcID(inputDeviceID, p)
            inputIOProcID = nil
            inputDeviceID = 0
        }
        engine.stop()
        isRunning = false
        os_unfair_lock_lock(bufferLock)
        rawLeftRMS = 0.0
        rawRightRMS = 0.0
        os_unfair_lock_unlock(bufferLock)
        DispatchQueue.main.async { [weak self] in
            self?.leftLevel = 0.0
            self?.rightLevel = 0.0
        }
    }

    public func restart() {
        restartWorkItem?.cancel()
        isRestarting = true
        stop(preserveRestarting: true)
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.isRestarting = false
            if !self.userStopped {
                self.start()
            }
        }
        restartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
    }

    // MARK: - Device helpers
 
    public static func liveDeviceID(for uid: String, fallbackID: AudioDeviceID) -> AudioDeviceID {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uidCF: CFString = uid as CFString
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafePointer(to: &uidCF) { qualPtr in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                UInt32(MemoryLayout<CFString>.size),
                qualPtr,
                &dataSize,
                &deviceID
            )
        }
        if status == noErr && deviceID != 0 && deviceID != kAudioObjectUnknown {
            return deviceID
        }
        return fallbackID
    }

    @discardableResult
    private func setDevice(_ deviceID: AudioDeviceID, on unit: AudioUnit) -> Bool {
        var devID = deviceID
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            print("Failed to set CurrentDevice \(deviceID): \(status)")
            return false
        }

        // Ask for a small hardware IO buffer (apps like Teams may have left a large one).
        var frames = preferredIOBufferFrames
        let bufStatus = AudioUnitSetProperty(
            unit,
            kAudioDevicePropertyBufferFrameSize,
            kAudioUnitScope_Global,
            0,
            &frames,
            UInt32(MemoryLayout<UInt32>.size)
        )
        if bufStatus != noErr {
            print("Could not set IO buffer size on device \(deviceID): \(bufStatus)")
        }
        return true
    }

    // MARK: - Ring buffer (realtime)

    /// Called on the capture device's IO thread.
    private func writeInput(left: UnsafePointer<Float>, right: UnsafePointer<Float>, frameCount: Int) {
        guard frameCount > 0 else { return }
        os_unfair_lock_lock(bufferLock)
        var w = writeFrame
        for i in 0..<frameCount {
            let idx = (w & Self.ringMask) &* 2
            ring[idx] = left[i]
            ring[idx + 1] = right[i]
            w &+= 1
        }
        writeFrame = w
        if frameCount > maxWriteChunk { maxWriteChunk = frameCount }
        os_unfair_lock_unlock(bufferLock)
    }

    /// Called on the output device's IO thread. Keeps latency pinned near a small target.
    private func readOutput(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frameCount: Int) {
        os_unfair_lock_lock(bufferLock)
        defer { os_unfair_lock_unlock(bufferLock) }

        let baseStep = resampleStep
        let needed = Double(frameCount) * baseStep + 2.0
        // Target = enough to absorb input IO bursts + output pull, with comfortable cushion for Bluetooth/system taps
        let chunkFrames = Double(max(maxWriteChunk, frameCount))
        let target = max(minTargetFrames, chunkFrames * 1.5 + needed)
        let maxFill = max(target * 3.0, target + 2048.0)

        var available = Double(writeFrame) - readPos

        // Too far behind (stall, drift, device switch) -> smoothly snap to target latency
        if available > maxFill || available < 0 {
            if writeFrame > 0 {
                readPos = max(0, Double(writeFrame) - target)
                available = Double(writeFrame) - readPos
                smoothedFill = available
            }
        }

        // Wait until we have a cushion before starting playback
        if !primed {
            if available >= target {
                primed = true
                smoothedFill = available
            } else {
                left.update(repeating: 0, count: frameCount)
                right.update(repeating: 0, count: frameCount)
                return
            }
        }

        // Under-run protection: if buffer dips below minimum needed, hold read position and output silence
        if available < needed {
            primed = false
            left.update(repeating: 0, count: frameCount)
            right.update(repeating: 0, count: frameCount)
            return
        }

        // Gentle drift compensation: speed up / slow down reading by at most 0.8%
        smoothedFill += (available - smoothedFill) * 0.05
        let err = max(-1.0, min(1.0, (smoothedFill - target) / target))
        let step = baseStep * (1.0 + err * 0.008)

        var pos = readPos
        for i in 0..<frameCount {
            let base = Int(pos)
            let frac = Float(pos - Double(base))
            let i0 = (base & Self.ringMask) &* 2
            let i1 = ((base &+ 1) & Self.ringMask) &* 2
            let l0 = ring[i0], r0 = ring[i0 + 1]
            left[i] = l0 + (ring[i1] - l0) * frac
            right[i] = r0 + (ring[i1 + 1] - r0) * frac
            pos += step
        }
        readPos = pos

        // MARK: - Realtime Affect De-escalator DSP
        if !isBypassed && (syllableLeveler > 0 || attackSoftener > 0 || breathGate > 0 || robotInharmonicity > 0) {
            let leveler = syllableLeveler
            let attackSoft = attackSoftener
            let gate = breathGate
            let inharmonic = robotInharmonicity
            let sampleRateFloat = Float(baseStep * 48000.0)
            let phaseInc = 2.0 * Float.pi * 65.0 / (sampleRateFloat > 0 ? sampleRateFloat : 48000.0)
            let attackCoeff: Float = 0.015
            let releaseCoeff: Float = 0.0004
            let transientThresh: Float = 0.065
            let recoveryRate: Float = 0.004
            let gateThresh: Float = 0.0015 + (gate * 0.018)

            var maxReduction: Float = 1.0
            var localTransientDamped: Float = 0.0

            for i in 0..<frameCount {
                var l = left[i]
                var r = right[i]

                // 1. Transient Softener (Damps aggressive plosives /p/, /t/, /k/)
                if attackSoft > 0 {
                    let diff = max(abs(l - prevL), abs(r - prevR))
                    if diff > transientThresh {
                        let targetGain = max(0.25, 1.0 - (attackSoft * min(1.0, (diff - transientThresh) * 6.5)))
                        if targetGain < transientGain {
                            transientGain = targetGain
                            localTransientDamped = max(localTransientDamped, 1.0 - targetGain)
                        }
                    }
                    transientGain += (1.0 - transientGain) * recoveryRate
                    l *= transientGain
                    r *= transientGain
                    prevL = l
                    prevR = r
                }

                // 2. Syllable Leveler (Flattens volume dynamics and shouting)
                let peak = max(abs(l), abs(r))
                if peak > levelerEnv {
                    levelerEnv += (peak - levelerEnv) * attackCoeff
                } else {
                    levelerEnv += (peak - levelerEnv) * releaseCoeff
                }

                if leveler > 0 && levelerEnv > 0.0001 {
                    let ratio: Float = 1.0 + (leveler * 16.0)
                    let thresh: Float = 0.045
                    var g: Float = 1.0
                    if levelerEnv > thresh {
                        g = pow(thresh / levelerEnv, 1.0 - (1.0 / ratio))
                    } else if levelerEnv > 0.004 {
                        g = 1.0 + leveler * 0.55 * (1.0 - levelerEnv / thresh)
                    }
                    if g < maxReduction { maxReduction = g }
                    l *= g
                    r *= g
                }

                // 3. Affect & Breath Gate (Cuts audible breathing, sighing, hesitation)
                if gate > 0 {
                    if levelerEnv < gateThresh {
                        gateGain += (0.0 - gateGain) * 0.06
                        breathGatedMeter = true
                    } else {
                        gateGain = 1.0
                        breathGatedMeter = false
                    }
                    l *= gateGain
                    r *= gateGain
                }

                // 4. Robotic Inharmonicity (Frequency carrier detachment)
                if inharmonic > 0 {
                    carrierPhase += phaseInc
                    if carrierPhase > 2.0 * Float.pi { carrierPhase -= 2.0 * Float.pi }
                    let mod = 0.5 + 0.5 * cos(carrierPhase)
                    let wetFactor = inharmonic * 0.65
                    l = (1.0 - wetFactor) * l + wetFactor * (l * mod * 1.5)
                    r = (1.0 - wetFactor) * r + wetFactor * (r * mod * 1.5)
                }

                left[i] = l
                right[i] = r
            }

            rawReductionDb = (maxReduction < 0.99) ? 20.0 * log10(max(0.05, maxReduction)) : 0.0
            if localTransientDamped > 0.05 {
                transientActivityMeter = max(transientActivityMeter, localTransientDamped)
            }
        } else {
            rawReductionDb = 0.0
            breathGatedMeter = false
        }
    }

    private func updatePitch() {
        let baseCents = (pitchSemitones * 100.0) + pitchCents
        let totalCents = baseCents + dynamicProsodyCorrectionCents
        let clampedCents = max(-2400.0, min(2400.0, totalCents))
        pitchNode.pitch = clampedCents
    }

    private func updateEQ() {
        guard eqNode.bands.count >= 2 else { return }
        let band0 = eqNode.bands[0]
        if cutoffFrequency >= 19900.0 {
            band0.bypass = true
        } else {
            band0.bypass = false
            band0.frequency = max(500.0, min(20000.0, cutoffFrequency))
        }

        let band1 = eqNode.bands[1]
        if urgencyNotchDb >= -0.5 {
            band1.bypass = true
        } else {
            band1.bypass = false
            band1.frequency = 3400.0
            band1.bandwidth = 1.5
            band1.gain = max(-18.0, min(0.0, urgencyNotchDb))
        }
    }

    private func updateMix() {
        if isBypassed {
            dryMixer.outputVolume = 1.0
            wetMixer.outputVolume = 0.0
        } else {
            dryMixer.outputVolume = 1.0 - dryWetMix
            wetMixer.outputVolume = dryWetMix
        }
    }

    private func updateBypass() {
        pitchNode.bypass = isBypassed
        if eqNode.bands.count >= 2 {
            eqNode.bands[0].bypass = isBypassed || (cutoffFrequency >= 19900.0)
            eqNode.bands[1].bypass = isBypassed || (urgencyNotchDb >= -0.5)
        }
        updateMix()
    }

    private func estimateF0FromBuffer(_ buffer: UnsafePointer<Float>, frameLength: Int, sampleRate: Float) -> (f0: Float, confidence: Float) {
        guard frameLength >= 256, sampleRate > 0 else { return (0, 0) }
        let n = min(frameLength, 512)
        let minLag = max(10, Int(sampleRate / 450.0))
        let maxLag = min(n / 2, Int(sampleRate / 70.0))
        guard maxLag > minLag else { return (0, 0) }

        var energy0: Float = 0
        vDSP_svesq(buffer, 1, &energy0, vDSP_Length(n - maxLag))
        guard energy0 > 1e-4 else { return (0, 0) }

        var bestLag = 0
        var bestCorr: Float = -1.0

        for lag in stride(from: minLag, through: maxLag, by: 2) {
            let len = n - lag
            var dot: Float = 0
            vDSP_dotpr(buffer, 1, buffer.advanced(by: lag), 1, &dot, vDSP_Length(len))
            var energyLag: Float = 0
            vDSP_svesq(buffer.advanced(by: lag), 1, &energyLag, vDSP_Length(len))
            let norm = sqrt(energy0 * energyLag)
            if norm > 1e-6 {
                let corr = dot / norm
                if corr > bestCorr {
                    bestCorr = corr
                    bestLag = lag
                }
            }
        }

        if bestLag > 0 && bestCorr > 0.35 {
            let f0 = sampleRate / Float(bestLag)
            return (f0, bestCorr)
        }
        return (0, 0)
    }

    private func installMeterTap(format: AVAudioFormat? = nil) {
        guard !meterTapInstalled else { return }
        let bufferSize: AVAudioFrameCount = 512

        outputMixer.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self = self, let channelData = buffer.floatChannelData else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else { return }

            let channelCount = Int(buffer.format.channelCount)
            var lRms: Float = 0.0
            var rRms: Float = 0.0

            vDSP_rmsqv(channelData[0], 1, &lRms, vDSP_Length(frameLength))

            if channelCount > 1 {
                vDSP_rmsqv(channelData[1], 1, &rRms, vDSP_Length(frameLength))
            } else {
                rRms = lRms
            }

            let lNorm = min(1.0, max(0.0, lRms * 3.5))
            let rNorm = min(1.0, max(0.0, rRms * 3.5))

            os_unfair_lock_lock(self.bufferLock)
            self.rawLeftRMS = lNorm
            self.rawRightRMS = rNorm
            os_unfair_lock_unlock(self.bufferLock)

            // Fast Pitch Inflection Tracking & Dynamic Flattening
            let detected = self.estimateF0FromBuffer(channelData[0], frameLength: frameLength, sampleRate: Float(buffer.format.sampleRate))
            var inPitch: Float = 0.0
            var outPitch: Float = 0.0
            var inCents: Float = 0.0
            var outCents: Float = 0.0

            if detected.f0 >= 65.0 && detected.f0 <= 500.0 {
                inPitch = detected.f0
                let anchor: Float = self.isRobotDrone ? 130.0 : 145.0
                inCents = 1200.0 * log2(max(60.0, detected.f0) / anchor)
                let flattenFactor = self.isRobotDrone ? 1.0 : self.prosodyFlatten
                let correction = -flattenFactor * inCents
                outCents = inCents + correction
                outPitch = anchor * pow(2.0, outCents / 1200.0)

                if self.prosodyFlatten > 0.05 || self.isRobotDrone {
                    self.dynamicProsodyCorrectionCents += (correction - self.dynamicProsodyCorrectionCents) * 0.35
                    self.updatePitch()
                } else if self.dynamicProsodyCorrectionCents != 0.0 {
                    self.dynamicProsodyCorrectionCents += (0.0 - self.dynamicProsodyCorrectionCents) * 0.2
                    self.updatePitch()
                }
            } else if self.dynamicProsodyCorrectionCents != 0.0 && self.prosodyFlatten <= 0.05 && !self.isRobotDrone {
                self.dynamicProsodyCorrectionCents += (0.0 - self.dynamicProsodyCorrectionCents) * 0.2
                self.updatePitch()
            }

            let curReduction = self.rawReductionDb
            let curTransient = self.transientActivityMeter
            let curGated = self.breathGatedMeter

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.leftLevel = max(lNorm, self.leftLevel * 0.82)
                self.rightLevel = max(rNorm, self.rightLevel * 0.82)

                self.currentGainReductionDb = curReduction
                self.transientDampedActivity = max(curTransient, self.transientDampedActivity * 0.82)
                self.transientActivityMeter *= 0.70
                self.breathGatedActive = curGated

                if inPitch > 0 {
                    self.inputPitchHz = inPitch
                    self.outputPitchHz = outPitch
                    self.pitchInflectionCents = inCents
                    self.flattenedInflectionCents = outCents
                } else {
                    self.pitchInflectionCents *= 0.90
                    self.flattenedInflectionCents *= 0.90
                }
                self.urgencyBandEnergyReduction = (self.urgencyNotchDb < -0.5) ? self.urgencyNotchDb : 0.0
            }
        }
        meterTapInstalled = true
    }

    private func removeMeterTap() {
        if meterTapInstalled {
            outputMixer.removeTap(onBus: 0)
            meterTapInstalled = false
        }
    }
}
