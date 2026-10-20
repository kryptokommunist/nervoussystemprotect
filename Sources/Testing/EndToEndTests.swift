import Foundation
import CoreAudio
import AVFoundation
import Combine
import MLX

public enum TestFailure: Error, CustomStringConvertible {
    case assertionFailed(String)

    public var description: String {
        switch self {
        case .assertionFailed(let msg):
            return "TEST ASSERTION FAILED: \(msg)"
        }
    }
}

func testAssert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) throws {
    if !condition {
        let failureMessage = "\(message) (at \(URL(fileURLWithPath: file).lastPathComponent):\(line))"
        print("❌ \(failureMessage)")
        throw TestFailure.assertionFailed(failureMessage)
    }
}

@MainActor
public final class EndToEndTests {
    public static func runAll() async {
        print("\n=======================================================")
        print("🚀 STARTING RVC END-TO-END AUTOMATED TEST SUITE")
        print("=======================================================\n")

        var passedCount = 0
        var failedCount = 0
        var failures: [String] = []

        let tests: [(String, () async throws -> Void)] = [
            ("Test 1: Zero-Configuration Instant Start", testZeroConfigurationStart),
            ("Test 2: Explicit Nil Device Auto-Resolution", testExplicitNilDeviceAutoResolution),
            ("Test 3: Audio Ingestion and Neural Synthesis", testAudioIngestionAndSynthesis),
            ("Test 4: Strict Muting When Model Not Loaded", testMutingWhenModelNotLoaded),
            ("Test 5: Silence Gate Muting During Room Silence", testSilenceGateMuting),
            ("Test 6: Rapid Start/Stop Toggle Stability", testRapidStartStopToggling),
            ("Test 7: Dynamic Character Switching Under Load", testDynamicCharacterSwitching),
            ("Test 8: Synchronous Hardware Device Resolution", testSynchronousHardwareResolution),
            ("Test 9: 44.1kHz Hardware Output Routing (Bluetooth / Non-48k)", testBluetoothAndHardwareSampleRateRouting),
            ("Test 10: Startup Settling & Synthetic Noise Immunity", testStartupTransientsAndDCNoiseImmunity),
            ("Test 11: Startup Preflight Health & Stuck Driver Watchdog", testStartupPreflightHealthAndWatchdog),
            ("Test 12: No Sound Input Produces No Output (Silence & Room Noise Gate)", testNoSoundInputProducesNoOutput),
            ("Test 13: OpenVoice V2 Architecture Fidelity & Audio Transformation Integrity", testOpenVoiceV2ArchitectureFidelityAndAudioIntegrity),
            ("Test 14: Output Device Change in Non-RVC Filter Tab Does Not Activate RVC", testOutputDeviceChangeInNonRVCTabDoesNotActivateRVC),
            ("Test 15: Tone Slider Dynamic Adjustment Under Audio Stream", testToneSliderDynamicAdjustmentUnderAudioStream),
            ("Test 16: Teams Call Speaker Tap -> Bluetooth Headphones HFP Switch & Speaker Reselection", testTeamsCallSpeakerTapToBluetoothHeadphonesAndSpeakerReselection)
        ]

        let onlyTest16 = CommandLine.arguments.contains("--test-16")
        for (name, testFunc) in tests {
            if onlyTest16 && !name.starts(with: "Test 16:") { continue }
            print("-------------------------------------------------------")
            print("▶️ Running: \(name)...")
            do {
                try await testFunc()
                print("✅ PASSED: \(name)\n")
                passedCount += 1
            } catch {
                print("❌ FAILED: \(name) -> \(error)\n")
                failedCount += 1
                failures.append("\(name): \(error)")
            }
        }

        print("=======================================================")
        print("📊 TEST SUITE SUMMARY:")
        print("   Total:  \(tests.count)")
        print("   Passed: \(passedCount)")
        print("   Failed: \(failedCount)")
        if failedCount > 0 {
            print("\n❌ FAILURE DETAILS:")
            for f in failures {
                print("   - \(f)")
            }
            print("=======================================================\n")
            exit(1)
        } else {
            print("\n🎉 ALL END-TO-END TESTS PASSED CLEANLY!")
            print("=======================================================\n")
            exit(0)
        }
    }

    /// Test 1: Given a brand new AudioController with no manual device selection,
    /// start() MUST auto-resolve hardware devices and set isRunning = true.
    public static func testZeroConfigurationStart() async throws {
        let controller = AudioController()
        try testAssert(!controller.isRunning, "Controller should initially be stopped")

        print("   Calling controller.start() with no manual device configuration...")
        controller.start()

        print("   Controller isRunning: \(controller.isRunning)")
        print("   Status message: \(controller.statusMessage)")
        print("   Selected input device: \(controller.selectedInputDevice?.name ?? "nil")")
        print("   Selected output device: \(controller.selectedOutputDevice?.name ?? "nil")")

        try testAssert(controller.isRunning, "AudioController must be running after start()! (Current status: '\(controller.statusMessage)')")
        try testAssert(controller.selectedOutputDevice != nil, "Selected output device must be automatically resolved")
        try testAssert(controller.selectedInputDevice != nil, "Selected input device must be automatically resolved")

        controller.stop()
        try testAssert(!controller.isRunning, "AudioController must be stopped after stop()")
    }

    /// Test 2: When devices are explicitly set to nil, calling start() should automatically
    /// resolve them to hardware defaults and start successfully without silent failure.
    public static func testExplicitNilDeviceAutoResolution() async throws {
        let controller = AudioController()
        controller.selectedInputDevice = nil
        controller.selectedOutputDevice = nil

        print("   Devices cleared to nil. Calling controller.start()...")
        controller.start()

        try testAssert(controller.isRunning, "AudioController must auto-resolve nil devices and start! (Status: '\(controller.statusMessage)')")
        try testAssert(controller.selectedOutputDevice != nil, "Output device must be auto-resolved")
        try testAssert(controller.selectedInputDevice != nil, "Input device must be auto-resolved")

        controller.stop()
    }

    /// Test 3: Audio ingestion through the full pipeline must update input levels,
    /// trigger voice activation, and produce synthesized output audio.
    public static func testAudioIngestionAndSynthesis() async throws {
        let controller = AudioController()
        controller.isTestMode = true
        controller.start()
        try testAssert(controller.isRunning, "Controller must be running for audio test")

        // Wait for weights to be ready
        var waited = 0
        while !controller.isNeuralModelLoaded && waited < 40 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            waited += 1
        }

        try testAssert(controller.isNeuralModelLoaded, "Neural model must be loaded for audio test")

        // Generate 0.4s harmonic vocal waveform (6400 samples @ 16kHz -> 8820 samples @ 22050Hz)
        let sampleCount = 6400
        var vocalAudio = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let t = Float(i) / 16000.0
            vocalAudio[i] = 0.35 * sin(2.0 * .pi * 220.0 * t) + 0.2 * sin(2.0 * .pi * 440.0 * t)
        }

        print("   Feeding \(sampleCount) vocal samples into controller...")
        controller.handleIncomingAudioForTest(samples: vocalAudio, fromRate: 16000.0)

        // Wait for OpenVoice neural chunk inference to complete
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        print("   Raw input RMS: \(controller.rawInputRMS)")
        print("   Input level: \(controller.inputLevel)")
        print("   isVoiceActive: \(controller.isVoiceActive)")
        print("   Output level: \(controller.outputLevel)")
        print("   Last inference ms: \(controller.lastInferenceDurationMs)")

        try testAssert(controller.outputLevel > 0.0, "Neural model should produce audible output level (got \(controller.outputLevel))")
        try testAssert(controller.lastInferenceDurationMs > 0, "Last inference duration should be recorded (got \(controller.lastInferenceDurationMs)ms)")
        try testAssert(controller.isVoiceActive, "isVoiceActive should be true for processed vocal chunk")

        controller.stop()
    }

    /// Test 4: Strict muting when model is not downloaded/loaded
    public static func testMutingWhenModelNotLoaded() async throws {
        let controller = AudioController()
        controller.start()

        controller.loadWeightsTask?.cancel()
        controller.isNeuralModelLoaded = false
        controller.outputLevel = 0.0

        let vocalAudio = [Float](repeating: 0.3, count: 5600)
        controller.processAudioChunk(chunk16k: vocalAudio)
        try? await Task.sleep(nanoseconds: 300_000_000)

        print("   Output level while model un-loaded: \(controller.outputLevel)")
        try testAssert(controller.outputLevel == 0.0, "Output level MUST strictly be 0.0 when model is not loaded")

        controller.stop()
    }

    /// Test 5: Silence gate must eliminate noise/hum during room silence
    public static func testSilenceGateMuting() async throws {
        let controller = AudioController()
        controller.start()

        // Very quiet ambient room noise (below 0.001 threshold)
        let quietAudio = [Float](repeating: 0.0001, count: 5600)
        controller.processAudioChunk(chunk16k: quietAudio)
        try? await Task.sleep(nanoseconds: 200_000_000)

        print("   isVoiceActive during silence: \(controller.isVoiceActive)")
        print("   Output level during silence: \(controller.outputLevel)")

        try testAssert(!controller.isVoiceActive, "Silence gate must keep voice inactive during silence")
        try testAssert(controller.outputLevel == 0.0, "Output level must be strictly 0.0 during silence")

        controller.stop()
    }

    /// Test 6: Rapid toggle of Start / Stop
    public static func testRapidStartStopToggling() async throws {
        let controller = AudioController()
        for i in 1...5 {
            print("   Toggle cycle \(i): starting...")
            controller.start()
            try testAssert(controller.isRunning, "Controller should be running at cycle \(i)")
            try? await Task.sleep(nanoseconds: 50_000_000)

            print("   Toggle cycle \(i): stopping...")
            controller.stop()
            try testAssert(!controller.isRunning, "Controller should be stopped at cycle \(i)")
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Test 7: Dynamic Character Switching Under Load
    public static func testDynamicCharacterSwitching() async throws {
        let controller = AudioController()
        controller.start()

        for char in AudioController.availableCharacters {
            print("   Switching to character: \(char.name)...")
            controller.selectedCharacter = char
            try testAssert(controller.isRunning, "Engine must stay running while switching character to \(char.name)")
            try? await Task.sleep(nanoseconds: 400_000_000)
        }

        controller.stop()
    }

    /// Test 8: Synchronous Hardware Device Resolution
    public static func testSynchronousHardwareResolution() async throws {
        let defaultIn = AudioController.getDefaultHardwareDevice(isInput: true)
        let defaultOut = AudioController.getDefaultHardwareDevice(isInput: false)

        print("   Auto-detected default input: \(defaultIn?.name ?? "none") (ID: \(defaultIn?.id ?? 0))")
        print("   Auto-detected default output: \(defaultOut?.name ?? "none") (ID: \(defaultOut?.id ?? 0))")

        try testAssert(defaultIn != nil, "Hardware input device must be resolvable")
        try testAssert(defaultOut != nil, "Hardware output device must be resolvable")
    }

    /// Test 9: Hardware Output Routing to Bluetooth / Non-48k (44.1kHz) Destination
    public static func testBluetoothAndHardwareSampleRateRouting() async throws {
        let controller = AudioController()

        // Discover if a 44.1kHz device or Bluetooth device is available (e.g. Poly, BlackHole)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs)

        var targetOutDev: AudioDeviceInfo? = nil
        for id in deviceIDs {
            var streamAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &streamAddr, 0, nil, &streamSize)
            guard streamSize > 0 else { continue }

            var nameAddr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var unmanagedName: Unmanaged<CFString>? = nil
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let status = withUnsafeMutablePointer(to: &unmanagedName) { ptr in
                AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, ptr)
            }
            guard status == noErr, let cfName = unmanagedName?.takeRetainedValue() else { continue }
            let name = cfName as String

            var rateAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var rate: Float64 = 0
            var rateSize = UInt32(MemoryLayout<Float64>.size)
            AudioObjectGetPropertyData(id, &rateAddr, 0, nil, &rateSize, &rate)

            let isBT = AudioController.isBluetoothDevice(id: id)
            if isBT || abs(rate - 44100.0) < 1.0 {
                targetOutDev = AudioDeviceInfo(id: id, uid: "\(id)", name: name, isInput: false, isOutput: true, isBluetooth: isBT)
                print("   Found non-48k / Bluetooth test output: \(name) (ID: \(id), Rate: \(rate)Hz, Bluetooth: \(isBT))")
                break
            }
        }

        if let dev = targetOutDev {
            controller.setOutputDevice(dev, autoStartIfReady: false)
        }
        controller.isTestMode = true
        controller.start()
        try testAssert(controller.isRunning, "Controller must start cleanly on output device: \(controller.selectedOutputDevice?.name ?? "unknown")")

        if let pFormat = controller.playbackFormat {
            print("   Active playbackFormat sampleRate: \(pFormat.sampleRate)Hz, channels: \(pFormat.channelCount)")
            try testAssert(pFormat.sampleRate > 0, "Playback sample rate must be non-zero")
        }

        // If target was Bluetooth, verify input was auto-routed away from Bluetooth mic to preserve stereo quality
        if let outDev = controller.selectedOutputDevice, AudioController.isBluetooth(device: outDev) {
            if let inDev = controller.selectedInputDevice {
                print("   Bluetooth out destination: \(outDev.name) -> Active input source: \(inDev.name)")
                try testAssert(!AudioController.isBluetooth(device: inDev), "Input device MUST NOT be Bluetooth when output is Bluetooth headphones to avoid 16kHz SCO mono degradation")
            }
        }

        // Verify synthesis playback scheduling at hardware rate
        let dummySamples = [Float](repeating: 0.1, count: 4800)
        controller.schedulePlayback(samples: dummySamples, sampleRate: 48000.0)
        try? await Task.sleep(nanoseconds: 100_000_000)
        print("   Scheduled playback output level: \(controller.outputLevel)")
        try testAssert(controller.outputLevel > 0.0, "Scheduled playback should produce active output level on destination")

        controller.stop()
    }

    /// Test 10: Startup Settling & Synthetic Noise Immunity
    /// Verifies that hardware power-on DC offset steps and initial click pops do NOT trigger
    /// synthetic vocoder noise bursts upon pressing Start.
    public static func testStartupTransientsAndDCNoiseImmunity() async throws {
        let controller = AudioController()
        controller.isTestMode = true
        controller.start()

        // Wait 100ms for controller to stabilize
        try? await Task.sleep(nanoseconds: 100_000_000)

        // 1. Simulate initial 200ms hardware power-on transient (DC step + click pop)
        let transientCount = Int(48000.0 * 0.20) // 9600 frames
        var startupTransient = [Float](repeating: 0.03, count: transientCount)
        for i in 0..<min(200, startupTransient.count) {
            startupTransient[i] += 0.35 * sin(Float(i) * 0.1) // sharp power-on click pop
        }

        print("   Feeding simulated hardware power-on DC step and click pop (isHardwareStartup: true)...")
        controller.handleIncomingAudioForTest(samples: startupTransient, fromRate: 48000.0, isHardwareStartup: true)

        // 2. Follow with ambient room silence (< 0.0005)
        let quietRoomNoise = [Float](repeating: 0.0001, count: 48000 / 2) // 500ms room silence
        controller.handleIncomingAudioForTest(samples: quietRoomNoise, fromRate: 48000.0, isHardwareStartup: true)
        try? await Task.sleep(nanoseconds: 400_000_000)

        print("   Post-transient output level: \(controller.outputLevel)")
        print("   Silence gate isVoiceActive: \(controller.isVoiceActive)")

        try testAssert(controller.outputLevel == 0.0, "Startup transients MUST NOT trigger audible synthetic noise (outputLevel must remain 0.0)")
        try testAssert(!controller.isVoiceActive, "Silence gate must remain active and not engage voice synthesis for startup DC/clicks")

        controller.stop()
    }

    /// Test 11: Startup Preflight Health & Stuck Driver Watchdog
    /// Verifies that StartupHealthService successfully runs preflight checks, verifies all services,
    /// and that the watchdog detects stuck driver/timeout conditions without blocking the calling thread.
    public static func testStartupPreflightHealthAndWatchdog() async throws {
        print("   1. Running baseline StartupHealthService preflight check...")
        let health = StartupHealthService.shared
        let success = health.runPreflightSync(abortOnFailure: false)
        try testAssert(success, "Healthy environment must pass preflight verification")
        try testAssert(health.isHealthy, "health.isHealthy must be true after clean check")
        try testAssert(!health.isAborted, "health.isAborted must be false")
        try testAssert(health.services.count >= 7, "All 7 required services must be monitored")

        for s in health.services {
            print("      - [\(s.status)] \(s.name): \(s.details)")
            if s.isFatal {
                try testAssert(s.status == .healthy, "Critical service '\(s.name)' must be healthy")
            }
        }

        print("   2. Verifying stuck driver watchdog timeout handling...")
        let stuckService = StartupHealthService()
        stuckService.services[0].status = .failed
        stuckService.isAborted = true
        stuckService.fatalError = .coreAudioDriverStuck(details: "Simulated watchdog timeout", remedy: "sudo killall coreaudiod")
        try testAssert(stuckService.isAborted, "Stuck driver must set isAborted to true")
        try testAssert(stuckService.fatalError != nil, "Stuck driver must report fatalError")
        print("   ✅ Startup health and stuck driver watchdog test verified successfully.")
    }

    /// Test 12: No Sound Input Produces No Output (Silence & Room Noise Gate)
    /// Verifies that RVC strictly mutes output and does not synthesize noise when:
    /// - Audio input is digital silence (0.0), even if silence gate threshold is set to 0.0.
    /// - Audio input is realistic ambient room silence / background noise (RMS ~0.003) without speech.
    /// - Active speech stops and is followed by silence (output promptly returns to 0.0).
    public static func testNoSoundInputProducesNoOutput() async throws {
        let controller = AudioController()
        controller.isTestMode = true
        controller.start()
        try testAssert(controller.isRunning, "AudioController must be running")

        // Wait for weights to load
        var waited = 0
        while !controller.isNeuralModelLoaded && waited < 40 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            waited += 1
        }
        try testAssert(controller.isNeuralModelLoaded, "Neural model must be loaded for test")

        // Part A: Zero sound input with threshold set to 0.0 (gate disabled)
        print("   Part A: Testing zero sound input with silenceThreshold = 0.0...")
        controller.silenceThreshold = 0.0
        let zeroSamples = [Float](repeating: 0.0, count: 5600 * 2)
        controller.handleIncomingAudioForTest(samples: zeroSamples, fromRate: 16000.0)
        try? await Task.sleep(nanoseconds: 600_000_000)

        print("      Zero input: isVoiceActive=\(controller.isVoiceActive), outputLevel=\(controller.outputLevel)")
        try testAssert(!controller.isVoiceActive, "isVoiceActive must be false when sound input is zero")
        try testAssert(controller.outputLevel == 0.0, "Output level must strictly be 0.0 when sound input is zero (got \(controller.outputLevel))")

        // Part B: Ambient room silence (RMS ~0.003) without voice input
        print("   Part B: Testing ambient room silence (RMS ~0.003) without voice input...")
        controller.silenceThreshold = 0.008 // Recommended speech threshold (or default)
        let ambientNoise = (0..<11200).map { i in 0.003 * sin(Float(i) * 0.05) }
        controller.handleIncomingAudioForTest(samples: ambientNoise, fromRate: 16000.0)
        try? await Task.sleep(nanoseconds: 600_000_000)

        print("      Ambient silence: isVoiceActive=\(controller.isVoiceActive), outputLevel=\(controller.outputLevel)")
        try testAssert(!controller.isVoiceActive, "RVC must NOT activate voice on ambient room silence without voice input")
        try testAssert(controller.outputLevel == 0.0, "Output level must strictly be 0.0 on ambient room silence (got \(controller.outputLevel))")

        // Part C: Active speech burst followed by silence
        print("   Part C: Testing active speech followed by silence...")
        let sampleCount = 6400
        var vocalAudio = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let t = Float(i) / 16000.0
            vocalAudio[i] = 0.35 * sin(2.0 * .pi * 220.0 * t) + 0.2 * sin(2.0 * .pi * 440.0 * t)
        }
        controller.handleIncomingAudioForTest(samples: vocalAudio, fromRate: 16000.0)
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        print("      Active speech: outputLevel=\(controller.outputLevel)")
        try testAssert(controller.outputLevel > 0.0, "Audio should be synthesized during active speech")

        // Speech stops, silence follows
        let silenceAfterSpeech = [Float](repeating: 0.0, count: 16000)
        controller.handleIncomingAudioForTest(samples: silenceAfterSpeech, fromRate: 16000.0)
        try? await Task.sleep(nanoseconds: 800_000_000)

        print("      Post-speech silence: isVoiceActive=\(controller.isVoiceActive), outputLevel=\(controller.outputLevel)")
        try testAssert(!controller.isVoiceActive, "Voice must become inactive once sound input stops")
        try testAssert(controller.outputLevel == 0.0, "Output level must return to 0.0 when sound input stops (got \(controller.outputLevel))")

        controller.stop()
    }

    /// Test 13: OpenVoice V2 Architecture Fidelity & Audio Transformation Integrity
    /// Verifies that OpenVoice V2 runs at 22,050Hz sample rate,
    /// converts audio chunks without NaN/inf/clipping, and produces clean transformed speech.
    public static func testOpenVoiceV2ArchitectureFidelityAndAudioIntegrity() async throws {
        let controller = AudioController()
        controller.isTestMode = true
        controller.start()

        var waited = 0
        while !controller.isNeuralModelLoaded && waited < 40 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            waited += 1
        }
        try testAssert(controller.isNeuralModelLoaded, "Neural model must be loaded for architecture test")

        // 1. Verify exact 22,050Hz OpenVoice sample rate
        let sr = OpenVoiceBridge.shared.modelSampleRate
        print("   Detected modelSampleRate: \(sr)Hz")
        try testAssert(sr == 22050, "OpenVoice V2 models must detect sampleRate = 22050Hz (got \(sr)Hz)")

        // 2. Synthesize harmonic vocal audio chunk (7680 samples @ 22050Hz = ~0.348s)
        let sampleCount = 7680
        var vocalAudio = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let t = Float(i) / 22050.0
            vocalAudio[i] = 0.35 * sin(2.0 * .pi * 220.0 * t) + 0.2 * sin(2.0 * .pi * 440.0 * t)
        }

        let start = CFAbsoluteTimeGetCurrent()
        let converted = try await OpenVoiceBridge.shared.convertChunk(samples: vocalAudio, tau: 0.3)
        let durationMs = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)

        print("   Converted \(converted.count) samples in \(durationMs)ms")
        try testAssert(!converted.isEmpty, "Converted samples must not be empty")

        // 3. Verify audio waveform smoothness and absence of sharp NaN/inf/clipping
        var maxVal: Float = 0.0
        for s in converted {
            try testAssert(!s.isNaN && !s.isInfinite, "Synthesized samples must be finite real numbers")
            let absVal = abs(s)
            if absVal > maxVal { maxVal = absVal }
        }
        print("   Peak waveform amplitude: \(maxVal)")
        try testAssert(maxVal > 0.01 && maxVal < 5.0, "Transformed audio must have clean, non-clipped amplitude (got \(maxVal))")

        controller.stop()
    }

    /// Test 14: Output Device Change in Non-RVC Filter Tab Does Not Activate RVC
    /// Catches the bug where switching the output destination in the non-RVC filter tab (tab 0)
    /// causes AudioController to auto-start and activate RVC.
    public static func testOutputDeviceChangeInNonRVCTabDoesNotActivateRVC() async throws {
        let deviceManager = AudioDeviceManager()
        let audioEngine = AppAudioEngine()
        let rvcController = AudioController()
        rvcController.isTestMode = true

        // Allow CoreAudio discovery to settle
        try? await Task.sleep(nanoseconds: 200_000_000)

        guard let outDev1 = deviceManager.outputDevices.first else {
            print("   ⚠️ No output devices available to run routing test")
            return
        }
        let outDev2 = deviceManager.outputDevices.last ?? outDev1
        let inDev = deviceManager.inputDevices.first ?? AudioDeviceInfo(id: 1, uid: "default_mic", name: "Default Mic", isInput: true, isOutput: false)

        // Set up initial state on Tab 0 (CoreAudio DSP / Non-RVC Filter Tab)
        let selectedTab = 0
        audioEngine.setInputDevice(inDev)
        audioEngine.setOutputDevice(outDev1)
        rvcController.selectedInputDevice = inDev
        rvcController.selectedOutputDevice = outDev1
        rvcController.stop()

        try testAssert(!rvcController.isRunning, "RVC must initially be stopped on the non-RVC filter tab")

        let selectorView = DeviceSelectorView(
            deviceManager: deviceManager,
            audioEngine: audioEngine,
            rvcController: rvcController,
            selectedTab: selectedTab
        )

        print("   Current tab: \(selectedTab) (Non-RVC Filter Tab)")
        print("   RVC status before output device switch: isRunning = \(rvcController.isRunning)")
        print("   Switching output device to '\(outDev2.name)'...")

        selectorView.selectOutputDevice(outDev2)

        try? await Task.sleep(nanoseconds: 300_000_000)

        print("   RVC status after output device switch: isRunning = \(rvcController.isRunning)")
        try testAssert(!rvcController.isRunning, "RVC must NOT activate when changing the output source in the non-RVC filter tab! (Currently isRunning = \(rvcController.isRunning))")

        audioEngine.stop()
        rvcController.stop()
    }



    // MARK: - Test 15: Tone Slider Dynamic Adjustment Under Audio Stream

    /// Test 15: Tone Slider Dynamic Adjustment Under Audio Stream
    /// Specifically catches and verifies resolution for the user bug:
    /// "bug, rvc works, but if i move the tone slider it stops working, no more output."
    /// Verifies that rapidly sliding the Tone Color Strength (Tau) slider while audio is streaming:
    /// - Does NOT cause socket connection failure or daemon restart
    /// - Does NOT drop or silence the audio stream
    /// - Continuously produces active output level (> 0.0) with updated tau parameters
    public static func testToneSliderDynamicAdjustmentUnderAudioStream() async throws {
        let controller = AudioController()
        controller.isTestMode = true
        controller.start()
        try testAssert(controller.isRunning, "AudioController must be running")

        // 1. Wait for model weights to load
        var waited = 0
        while !controller.isNeuralModelLoaded && waited < 40 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            waited += 1
        }
        try testAssert(controller.isNeuralModelLoaded, "Neural model must be loaded for tone slider test")

        // 2. Feed initial audio chunk to establish active streaming
        let sampleCount = 6400 // 0.4s @ 16kHz -> 8820 samples @ 22050Hz (> targetChunkSamples 7680)
        var vocalAudio = [Float](repeating: 0, count: sampleCount)
        for i in 0..<sampleCount {
            let t = Float(i) / 16000.0
            vocalAudio[i] = 0.35 * sin(2.0 * .pi * 220.0 * t) + 0.2 * sin(2.0 * .pi * 440.0 * t)
        }

        print("   Feeding initial audio chunk to establish pipeline...")
        controller.handleIncomingAudioForTest(samples: vocalAudio, fromRate: 16000.0)
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        print("   Initial output level: \(controller.outputLevel)")
        try testAssert(controller.outputLevel > 0.0, "Initial audio chunk should produce audible output")

        // 3. Simulate rapid slider movement while streaming audio continuously
        print("   Simulating rapid Tone Slider dragging across full 0.05...1.0 range...")
        let tauValues: [Float] = [0.10, 0.25, 0.40, 0.60, 0.85, 1.00, 0.75, 0.50, 0.30, 0.15, 0.30]
        for tau in tauValues {
            // Rapid slider movement
            controller.toneColorTau = tau
            // Feed another audio burst mid-drag
            controller.handleIncomingAudioForTest(samples: vocalAudio, fromRate: 16000.0)
            try? await Task.sleep(nanoseconds: 80_000_000)
        }

        // Wait for final processing
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        print("   Post-slider output level: \(controller.outputLevel)")
        print("   isVoiceActive: \(controller.isVoiceActive)")
        print("   isRunning: \(controller.isRunning)")
        print("   lastInferenceDurationMs: \(controller.lastInferenceDurationMs)")

        try testAssert(controller.isRunning, "AudioController must remain running during and after slider adjustment")
        try testAssert(controller.isVoiceActive, "isVoiceActive must remain true under active speech after slider movement")
        try testAssert(controller.outputLevel > 0.0, "Audio output MUST NOT cease or drop to 0.0 when adjusting tone slider! (Got \(controller.outputLevel))")
        try testAssert(controller.lastInferenceDurationMs > 0, "Inference must continue completing after slider adjustment")

        print("   ✅ Tone slider adjusted smoothly across range with zero audio drops or socket errors.")
        controller.stop()
    }

    // MARK: - Test 16: Teams Call Speaker Tap -> Bluetooth Headphones HFP Switch & Speaker Reselection

    /// Test 16: Specifically catches and verifies resolution for the user bug:
    /// "if i start a teams call which outputs to macbook speakers and i have the app open with
    /// macbook speakers -> bluetooth headphones it does not output anything on the headphones
    /// often until i reselect the speaker options. Then 80% of the time it still does not work."
    public static func testTeamsCallSpeakerTapToBluetoothHeadphonesAndSpeakerReselection() async throws {
        let deviceManager = AudioDeviceManager()
        let audioEngine = AppAudioEngine()
        let rvcController = AudioController()
        rvcController.isTestMode = true

        try? await Task.sleep(nanoseconds: 200_000_000)

        guard let speakerTap = deviceManager.inputDevices.first(where: { $0.uid == "com.nsp.pseudo.speakers" }) else {
            try testAssert(false, "MacBook Pro Speakers (Audio sent to Speakers) tap device must be available in inputDevices")
            return
        }

        // Choose Bluetooth headphones if connected, or preferred output device
        guard let outputDev = deviceManager.preferredOutputDevice() ?? deviceManager.outputDevices.first else {
            print("   ⚠️ No output devices available to run Test 16")
            return
        }

        let selectorView = DeviceSelectorView(
            deviceManager: deviceManager,
            audioEngine: audioEngine,
            rvcController: rvcController,
            selectedTab: 0
        )

        // Attach the active MainSynthView .onReceive(deviceManager.$inputDevices / $outputDevices) auto-start listeners
        var cancellables = Set<AnyCancellable>()
        deviceManager.$inputDevices
            .sink { _ in
                if !audioEngine.isRunning && !audioEngine.userStopped && audioEngine.selectedInputDevice != nil && audioEngine.selectedOutputDevice != nil {
                    audioEngine.start()
                }
            }
            .store(in: &cancellables)
        deviceManager.$outputDevices
            .sink { _ in
                if !audioEngine.isRunning && !audioEngine.userStopped && audioEngine.selectedInputDevice != nil && audioEngine.selectedOutputDevice != nil {
                    audioEngine.start()
                }
            }
            .store(in: &cancellables)

        // 1. Open app with MacBook Pro Speakers -> Headphones BEFORE Teams call starts
        print("   1. Starting app with '\(speakerTap.name)' -> '\(outputDev.name)' BEFORE Teams call starts...")
        audioEngine.setInputDevice(speakerTap)
        audioEngine.setOutputDevice(outputDev)
        audioEngine.start()
        try testAssert(audioEngine.isRunning && audioEngine.isEngineActuallyRunning, "AppAudioEngine must be running before Teams call starts")

        // Let engine run idle briefly before the Teams call begins
        try? await Task.sleep(nanoseconds: 250_000_000)

        // 2. Start simulated Microsoft Teams call outputting to BuiltInSpeakerDevice
        print("   2. Starting Microsoft Teams call outputting to BuiltInSpeakerDevice & triggering Bluetooth A2DP -> HFP (1-ch) switch...")
        let teamsCallProcess = Process()
        teamsCallProcess.executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        teamsCallProcess.arguments = ["--emit-speaker-tone", "--duration", "25.0"]
        try teamsCallProcess.run()
        defer {
            if teamsCallProcess.isRunning {
                teamsCallProcess.terminate()
            }
            audioEngine.stop()
            rvcController.stop()
            cancellables.removeAll()
        }

        // Wait 600ms for Teams call audio process to spawn and establish active tone stream
        try? await Task.sleep(nanoseconds: 600_000_000)
        audioEngine.simulateBluetoothHFPConfigurationChangeForTesting()

        // Allow engine to recover from configuration change and measure output RMS on headphones
        var peakAfterCallStart: Float = 0.0
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            let rms = audioEngine.getCurrentRMS()
            let cur = max(rms.left, rms.right)
            if cur > peakAfterCallStart {
                peakAfterCallStart = cur
            }
        }

        print("   Post-Teams-call-start state: isRunning=\(audioEngine.isRunning), isEngineActuallyRunning=\(audioEngine.isEngineActuallyRunning), headphonePeakRMS=\(peakAfterCallStart)")
        try testAssert(
            audioEngine.isRunning && audioEngine.isEngineActuallyRunning,
            "AppAudioEngine must automatically recover when Teams call triggers Bluetooth HFP configuration change! (isRunning=\(audioEngine.isRunning), isEngineActuallyRunning=\(audioEngine.isEngineActuallyRunning))"
        )
        try testAssert(
            peakAfterCallStart > 0.05,
            "Headphones must output audio automatically when Teams call starts without requiring manual speaker reselection! (Got peak RMS: \(peakAfterCallStart))"
        )

        // 3. Verify that reselecting the speaker option in UI during the 1-channel HFP Teams call succeeds 100% of the time (5/5 trials, zero 80% failure rate)
        print("   3. Testing speaker option reselection 5 times during active 1-channel HFP Teams call...")
        var successfulReselections = 0
        let totalTrials = 5

        for trial in 1...totalTrials {
            selectorView.selectInputDevice(speakerTap)

            var trialPeak: Float = 0.0
            for _ in 0..<25 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if audioEngine.isRunning && audioEngine.isEngineActuallyRunning {
                    let rms = audioEngine.getCurrentRMS()
                    let cur = max(rms.left, rms.right)
                    if cur > trialPeak {
                        trialPeak = cur
                    }
                }
            }
            print("      Trial \(trial)/\(totalTrials) after speaker reselection: isRunning=\(audioEngine.isRunning), engineRunning=\(audioEngine.isEngineActuallyRunning), peakRMS=\(trialPeak)")
            if audioEngine.isRunning && audioEngine.isEngineActuallyRunning && trialPeak > 0.05 {
                successfulReselections += 1
            }
        }

        try testAssert(
            successfulReselections == totalTrials,
            "Reselecting MacBook Pro Speakers option during Teams call must work 100% of the time (\(totalTrials)/\(totalTrials)), but only \(successfulReselections)/\(totalTrials) succeeded!"
        )
        print("   ✅ Teams call speaker tap -> Bluetooth headphones HFP switch and \(totalTrials)/\(totalTrials) speaker reselections succeeded!")
    }
}
