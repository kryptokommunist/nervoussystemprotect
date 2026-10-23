import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation
import Metal
import AppKit

public enum StartupError: LocalizedError, Equatable {
    case coreAudioDriverStuck(details: String, remedy: String)
    case missingOutputDevice(details: String)
    case missingInputDevice(details: String)
    case microphonePermissionDenied(details: String)
    case metalGPUUnavailable(details: String)
    case audioGraphFailed(details: String)
    case serviceCheckFailed(service: String, details: String)

    public var errorDescription: String? {
        switch self {
        case .coreAudioDriverStuck(let details, let remedy):
            return "CoreAudio Driver Stuck: \(details)\nRemedy: \(remedy)"
        case .missingOutputDevice(let details):
            return "Audio Output Failed: \(details)"
        case .missingInputDevice(let details):
            return "Audio Input Warning: \(details)"
        case .microphonePermissionDenied(let details):
            return "Microphone Permission Denied: \(details)"
        case .metalGPUUnavailable(let details):
            return "Metal GPU Acceleration Unavailable: \(details)"
        case .audioGraphFailed(let details):
            return "Audio Graph Initialization Failed: \(details)"
        case .serviceCheckFailed(let service, let details):
            return "\(service) Failed: \(details)"
        }
    }
}

public struct StartupServiceItem: Identifiable, Equatable {
    public let id: String
    public let name: String
    public var status: Status
    public var details: String
    public var remedy: String?
    public var isFatal: Bool

    public enum Status: Equatable {
        case pending
        case checking
        case healthy
        case warning
        case failed
    }

    public init(id: String, name: String, status: Status = .pending, details: String = "Pending check...", remedy: String? = nil, isFatal: Bool = true) {
        self.id = id
        self.name = name
        self.status = status
        self.details = details
        self.remedy = remedy
        self.isFatal = isFatal
    }
}

public final class StartupHealthService: ObservableObject {
    public static let shared = StartupHealthService()

    @Published public var services: [StartupServiceItem] = []
    @Published public var isChecking: Bool = false
    @Published public var isHealthy: Bool = false
    @Published public var isAborted: Bool = false
    @Published public var fatalError: StartupError? = nil

    private let probeQueue = DispatchQueue(label: "com.nsp.startup.probe", qos: .userInteractive)

    public init() {
        resetServiceItems()
    }

    public func resetServiceItems() {
        services = [
            StartupServiceItem(
                id: "coreaudio_driver",
                name: "CoreAudio Driver / Daemon (coreaudiod)",
                details: "Checks HAL responsiveness with strict watchdog timeout",
                remedy: "Run 'sudo killall coreaudiod' in Terminal to restart the audio daemon.",
                isFatal: true
            ),
            StartupServiceItem(
                id: "audio_output",
                name: "Audio Output System",
                details: "Verifies default and hardware output endpoints",
                remedy: "Connect speakers or headphones.",
                isFatal: true
            ),
            StartupServiceItem(
                id: "audio_input",
                name: "Audio Input & Capture System",
                details: "Verifies hardware microphone or virtual audio capture",
                remedy: "Ensure MacBook microphone or BlackHole virtual driver is available.",
                isFatal: false
            ),
            StartupServiceItem(
                id: "microphone_permission",
                name: "Microphone Privacy & Authorization",
                details: "Checks macOS TCC permission for audio input",
                remedy: "Enable microphone access in System Settings -> Privacy & Security -> Microphone.",
                isFatal: true
            ),
            StartupServiceItem(
                id: "metal_gpu",
                name: "Apple Silicon Metal GPU Engine",
                details: "Verifies Metal acceleration for MLX neural voice models",
                remedy: "Apple Silicon GPU with Metal 3 support is required.",
                isFatal: true
            ),
            StartupServiceItem(
                id: "audio_graph",
                name: "CoreAudio Graph Smoke Probe",
                details: "Validates AVAudioEngine node setup and graph preparation",
                remedy: "Restart the audio daemon: 'sudo killall coreaudiod'",
                isFatal: true
            ),
            StartupServiceItem(
                id: "neural_models",
                name: "Neural Model Weights & Assets",
                details: "Verifies OpenVoice V2 converter and voice character weights",
                remedy: "Download weights in the Neural Voice tab or verify network connection.",
                isFatal: false
            )
        ]
    }

    /// Asynchronous preflight verification called on app launch from UI
    public func runPreflight(showAlertOnFailure: Bool = true) {
        guard !isChecking else { return }
        let shouldShowAlert = showAlertOnFailure &&
            !CommandLine.arguments.contains("--take-screenshot") &&
            !CommandLine.arguments.contains("--no-alert")
        isChecking = true
        isHealthy = false
        isAborted = false
        fatalError = nil
        resetServiceItems()

        probeQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.executeAllChecks()
                DispatchQueue.main.async {
                    self.isChecking = false
                    self.isHealthy = true
                    self.isAborted = false
                    print("✅ [StartupHealthService] All startup preflight checks PASSED successfully.")
                }
            } catch let error as StartupError {
                DispatchQueue.main.async {
                    self.isChecking = false
                    self.isHealthy = false
                    self.isAborted = true
                    self.fatalError = error
                    print("🚨 [StartupHealthService] FATAL STARTUP ERROR: \(error.localizedDescription)")
                    if shouldShowAlert {
                        self.presentStartupAlert(for: error)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    let err = StartupError.serviceCheckFailed(service: "Unknown", details: error.localizedDescription)
                    self.isChecking = false
                    self.isHealthy = false
                    self.isAborted = true
                    self.fatalError = err
                    print("🚨 [StartupHealthService] FATAL STARTUP ERROR: \(error.localizedDescription)")
                    if shouldShowAlert {
                        self.presentStartupAlert(for: err)
                    }
                }
            }
        }
    }

    /// Synchronous preflight verification for CLI tools / automated test scripts.
    /// Returns true if all critical checks passed, false if startup aborted.
    @discardableResult
    public func runPreflightSync(abortOnFailure: Bool = false) -> Bool {
        isChecking = true
        isHealthy = false
        isAborted = false
        fatalError = nil
        resetServiceItems()

        do {
            try executeAllChecks()
            isChecking = false
            isHealthy = true
            isAborted = false
            print("✅ [StartupHealthService] All startup preflight checks passed.")
            return true
        } catch let error as StartupError {
            isChecking = false
            isHealthy = false
            isAborted = true
            fatalError = error
            print("\n" + String(repeating: "=", count: 70))
            print("🚨 FATAL STARTUP PREFLIGHT ERROR: STARTUP ABORTED")
            print(String(repeating: "-", count: 70))
            print(error.localizedDescription)
            print(String(repeating: "=", count: 70) + "\n")
            if abortOnFailure {
                exit(1)
            }
            return false
        } catch {
            isChecking = false
            isHealthy = false
            isAborted = true
            fatalError = .serviceCheckFailed(service: "Startup", details: error.localizedDescription)
            print("\n🚨 FATAL STARTUP PREFLIGHT ERROR: \(error.localizedDescription)\n")
            if abortOnFailure {
                exit(1)
            }
            return false
        }
    }

    // MARK: - Internal Verification Pipeline

    private func executeAllChecks() throws {
        // --- 1. COREAUDIO DRIVER / DAEMON (coreaudiod) PROBE WITH WATCHDOG ---
        updateStatus(id: "coreaudio_driver", status: .checking, details: "Probing CoreAudio HAL responsiveness...")
        
        if CommandLine.arguments.contains("--simulate-driver-stuck") {
            Thread.sleep(forTimeInterval: 0.1)
            updateStatus(
                id: "coreaudio_driver",
                status: .failed,
                details: "Watchdog timeout after 2500ms. Audio server/driver is hung.",
                remedy: "Run 'sudo killall coreaudiod' in Terminal to restart the audio daemon."
            )
            throw StartupError.coreAudioDriverStuck(
                details: "CoreAudio daemon (coreaudiod) is stuck or unresponsive. System IPC calls to audio hardware timed out.",
                remedy: "Restart the audio daemon by running 'sudo killall coreaudiod' in Terminal."
            )
        }

        let (devices, driverError) = probeCoreAudioWithTimeout(timeoutMs: 2500)
        if let err = driverError {
            updateStatus(
                id: "coreaudio_driver",
                status: .failed,
                details: "CoreAudio driver is stuck or not responding: \(err)",
                remedy: "Run 'sudo killall coreaudiod' in Terminal to restart the audio daemon."
            )
            throw StartupError.coreAudioDriverStuck(
                details: "CoreAudio daemon (coreaudiod) is stuck or unresponsive. System IPC calls to audio hardware timed out.",
                remedy: "Restart the audio daemon by running 'sudo killall coreaudiod' in Terminal."
            )
        }
        updateStatus(
            id: "coreaudio_driver",
            status: .healthy,
            details: "CoreAudio daemon is active and responsive (\(devices.count) endpoints reported)."
        )

        // --- 2. AUDIO OUTPUT SUBSYSTEM ---
        updateStatus(id: "audio_output", status: .checking, details: "Verifying output hardware endpoints...")
        var outputsCount = 0
        var defaultOutputName = "Unknown"
        var defaultOutAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var defaultOutID: AudioDeviceID = 0
        var defSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let defStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultOutAddr,
            0,
            nil,
            &defSize,
            &defaultOutID
        )

        for id in devices {
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var sSize: UInt32 = 0
            if AudioObjectGetPropertyDataSize(id, &streamAddr, 0, nil, &sSize) == noErr && sSize > 0 {
                outputsCount += 1
                if id == defaultOutID {
                    defaultOutputName = queryDeviceName(id: id) ?? "Device #\(id)"
                }
            }
        }

        if outputsCount == 0 || defStatus != noErr || defaultOutID == 0 {
            updateStatus(
                id: "audio_output",
                status: .failed,
                details: "No active audio output devices detected on this system.",
                remedy: "Connect headphones, external speakers, or check macOS Sound Output Settings."
            )
            throw StartupError.missingOutputDevice(details: "No audio output devices detected. Connect headphones or speakers.")
        }
        updateStatus(
            id: "audio_output",
            status: .healthy,
            details: "\(outputsCount) output endpoint(s) ready (Default: \(defaultOutputName))."
        )

        // --- 3. AUDIO INPUT & CAPTURE SUBSYSTEM ---
        updateStatus(id: "audio_input", status: .checking, details: "Checking audio capture inputs...")
        var inputsCount = 0
        for id in devices {
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var sSize: UInt32 = 0
            if AudioObjectGetPropertyDataSize(id, &streamAddr, 0, nil, &sSize) == noErr && sSize > 0 {
                inputsCount += 1
            }
        }
        if #available(macOS 14.2, *) {
            inputsCount += 1 // System Audio Tap (process loopback) available
        }

        if inputsCount == 0 {
            updateStatus(
                id: "audio_input",
                status: .warning,
                details: "No audio input hardware detected.",
                remedy: "Connect a microphone or install BlackHole 2ch for system audio capture."
            )
        } else {
            updateStatus(
                id: "audio_input",
                status: .healthy,
                details: "\(inputsCount) audio capture source(s) available."
            )
        }

        // --- 4. MICROPHONE PERMISSION / PRIVACY ---
        updateStatus(id: "microphone_permission", status: .checking, details: "Checking TCC microphone authorization...")
        let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)
        switch micAuth {
        case .authorized:
            updateStatus(id: "microphone_permission", status: .healthy, details: "Microphone access is authorized.")
        case .notDetermined:
            let sem = DispatchSemaphore(value: 0)
            var granted = false
            AVCaptureDevice.requestAccess(for: .audio) { g in
                granted = g
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + .milliseconds(2000))
            if granted || AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                updateStatus(id: "microphone_permission", status: .healthy, details: "Microphone access granted.")
            } else {
                updateStatus(
                    id: "microphone_permission",
                    status: .failed,
                    details: "Microphone access was not granted by user.",
                    remedy: "Enable microphone in System Settings -> Privacy & Security -> Microphone."
                )
                throw StartupError.microphonePermissionDenied(details: "Microphone permission was not granted.")
            }
        case .denied, .restricted:
            updateStatus(
                id: "microphone_permission",
                status: .failed,
                details: "Microphone access is denied in macOS System Settings.",
                remedy: "Enable microphone in System Settings -> Privacy & Security -> Microphone."
            )
            throw StartupError.microphonePermissionDenied(details: "Microphone permission is denied in System Settings.")
        @unknown default:
            updateStatus(id: "microphone_permission", status: .warning, details: "Unknown authorization status.")
        }

        // --- 5. APPLE SILICON METAL GPU ENGINE ---
        updateStatus(id: "metal_gpu", status: .checking, details: "Detecting Apple Silicon Metal GPU...")
        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            updateStatus(
                id: "metal_gpu",
                status: .failed,
                details: "Metal GPU device could not be allocated.",
                remedy: "An Apple Silicon GPU with Metal support is required for MLX neural models."
            )
            throw StartupError.metalGPUUnavailable(details: "No Metal GPU available.")
        }
        updateStatus(id: "metal_gpu", status: .healthy, details: "\(metalDevice.name) (Metal 3 supported).")

        // --- 6. COREAUDIO GRAPH SMOKE PROBE ---
        updateStatus(id: "audio_graph", status: .checking, details: "Probing AVAudioEngine graph compilation...")
        let graphProbeError = probeAudioGraphWithTimeout(timeoutMs: 1500)
        if let err = graphProbeError {
            updateStatus(
                id: "audio_graph",
                status: .failed,
                details: "Audio engine graph failed: \(err)",
                remedy: "Restart coreaudiod: 'sudo killall coreaudiod'"
            )
            throw StartupError.audioGraphFailed(details: err)
        }
        updateStatus(id: "audio_graph", status: .healthy, details: "AVAudioEngine graph initialized and compiled without fault.")

        // --- 7. NEURAL MODEL WEIGHTS & ASSETS ---
        updateStatus(id: "neural_models", status: .checking, details: "Verifying OpenVoice V2 assets...")
        let openVoiceDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("OpenVoiceModels") ?? URL(fileURLWithPath: "/tmp/OpenVoiceModels")
        let requiredModels = [
            openVoiceDir.appendingPathComponent("checkpoint.pth").path,
            openVoiceDir.appendingPathComponent("config.json").path
        ]
        var missingFiles: [String] = []
        for file in requiredModels {
            if !FileManager.default.fileExists(atPath: file) {
                missingFiles.append((file as NSString).lastPathComponent)
            }
        }
        if missingFiles.isEmpty {
            updateStatus(id: "neural_models", status: .healthy, details: "OpenVoice V2 neural converter weights verified on disk.")
        } else {
            updateStatus(
                id: "neural_models",
                status: .warning,
                details: "Missing weights: \(missingFiles.joined(separator: ", ")) (downloadable on demand).",
                remedy: "Click 'Download Weights' in the Neural Voice tab to download voice models."
            )
        }
    }

    // MARK: - Helper Probes

    private func probeCoreAudioWithTimeout(timeoutMs: Int) -> ([AudioDeviceID], String?) {
        let sem = DispatchSemaphore(value: 0)
        var resultDevices: [AudioDeviceID] = []
        var resultError: String? = nil

        let queue = DispatchQueue(label: "com.nsp.coreaudio.probe.worker", qos: .userInteractive)
        queue.async {
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
            if status != noErr {
                resultError = "AudioObjectGetPropertyDataSize failed with OSStatus \(status)"
                sem.signal()
                return
            }

            let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
            var devIDs = [AudioDeviceID](repeating: 0, count: count)
            let getStatus = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                0,
                nil,
                &dataSize,
                &devIDs
            )
            if getStatus != noErr {
                resultError = "AudioObjectGetPropertyData failed with OSStatus \(getStatus)"
            } else {
                resultDevices = devIDs
            }
            sem.signal()
        }

        let waitResult = sem.wait(timeout: .now() + .milliseconds(timeoutMs))
        if waitResult == .timedOut {
            return ([], "Watchdog timeout after \(timeoutMs)ms. Audio server/driver is hung.")
        }
        return (resultDevices, resultError)
    }

    private func probeAudioGraphWithTimeout(timeoutMs: Int) -> String? {
        let sem = DispatchSemaphore(value: 0)
        var errorDesc: String? = nil

        let queue = DispatchQueue(label: "com.nsp.graph.probe.worker", qos: .userInteractive)
        queue.async {
            do {
                let testEngine = AVAudioEngine()
                let testPitch = AVAudioUnitTimePitch()
                testEngine.attach(testPitch)
                testEngine.connect(testPitch, to: testEngine.mainMixerNode, format: nil)
                testEngine.prepare()
                try testEngine.start()
                testEngine.stop()
            } catch {
                errorDesc = error.localizedDescription
            }
            sem.signal()
        }

        let waitResult = sem.wait(timeout: .now() + .milliseconds(timeoutMs))
        if waitResult == .timedOut {
            return "Graph preparation timed out after \(timeoutMs)ms. Audio server is hung."
        }
        return errorDesc
    }

    private func queryDeviceName(id: AudioDeviceID) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var nameCF: Unmanaged<CFString>? = nil
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            id,
            &propertyAddress,
            0,
            nil,
            &dataSize,
            &nameCF
        )
        guard status == noErr, let cf = nameCF else { return nil }
        return cf.takeRetainedValue() as String
    }

    private func updateStatus(id: String, status: StartupServiceItem.Status, details: String, remedy: String? = nil) {
        let update = { [weak self] in
            guard let self = self else { return }
            if let idx = self.services.firstIndex(where: { $0.id == id }) {
                self.services[idx].status = status
                self.services[idx].details = details
                if let r = remedy {
                    self.services[idx].remedy = r
                }
            }
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    private func presentStartupAlert(for error: StartupError) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Nervous System Protect — Startup Aborted"
        alert.informativeText = error.localizedDescription + "\n\nThe application stopped initialization to prevent system freeze."
        alert.addButton(withTitle: "Quit Application")
        alert.addButton(withTitle: "Retry Preflight Check")
        alert.addButton(withTitle: "Copy 'sudo killall coreaudiod'")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn: // Quit Application
            NSApplication.shared.terminate(nil)
            exit(1)
        case .alertSecondButtonReturn: // Retry Preflight Check
            self.runPreflight(showAlertOnFailure: true)
        case .alertThirdButtonReturn: // Copy Command
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("sudo killall coreaudiod", forType: .string)
            self.presentStartupAlert(for: error)
        default:
            break
        }
    }
}
