import Foundation
import AVFoundation
import AudioToolbox
import Accelerate
import MLX
import MLXNN

public struct VoiceCharacter: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let speakerEmbeddingFileName: String
    public let defaultTau: Float
    public let defaultPitch: Int
    public let description: String

    // Backwards compatibility accessors
    public var modelFileName: String { speakerEmbeddingFileName }
    public var indexFileName: String { speakerEmbeddingFileName }

    public init(id: String, name: String, speakerEmbeddingFileName: String, defaultTau: Float = 0.3, defaultPitch: Int = 0, description: String = "") {
        self.id = id
        self.name = name
        self.speakerEmbeddingFileName = speakerEmbeddingFileName
        self.defaultTau = defaultTau
        self.defaultPitch = defaultPitch
        self.description = description
    }
}

public enum ModelLoadStatus: Equatable {
    case ready(character: String, hasIndex: Bool, latencyMs: Int)
    case missing(files: [String])
    case loading(character: String)
    case downloading(progress: Double, fileName: String)
    case failed(error: String)
}

public struct VoicePreset: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public var name: String
    public var emoji: String
    public var description: String
    public var characterId: String
    public var pitchShift: Float
    public var indexRate: Float
    public var silenceThreshold: Float
    public var isBuiltin: Bool

    public init(
        id: String,
        name: String,
        emoji: String,
        description: String,
        characterId: String,
        pitchShift: Float,
        indexRate: Float = 0.3,
        silenceThreshold: Float = 0.008,
        isBuiltin: Bool = false
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.description = description
        self.characterId = characterId
        self.pitchShift = pitchShift
        self.indexRate = indexRate
        self.silenceThreshold = silenceThreshold
        self.isBuiltin = isBuiltin
    }
}

@MainActor
public final class AudioController: ObservableObject {
    public static let availableCharacters: [VoiceCharacter] = [
        VoiceCharacter(
            id: "american_executive",
            name: "American Executive (Warm Baritone)",
            speakerEmbeddingFileName: "ses/en-us.pth",
            defaultTau: 0.3,
            defaultPitch: -2,
            description: "Deep, articulate US executive presence with confident resonant lows"
        ),
        VoiceCharacter(
            id: "british_authority",
            name: "British Authority (Calm Deep)",
            speakerEmbeddingFileName: "ses/en-default.pth",
            defaultTau: 0.3,
            defaultPitch: -4,
            description: "Calm, composed BBC-style authority to de-escalate tension"
        ),
        VoiceCharacter(
            id: "australian_negotiator",
            name: "Australian Negotiator (Warm Mid)",
            speakerEmbeddingFileName: "ses/en-au.pth",
            defaultTau: 0.35,
            defaultPitch: 0,
            description: "Crisp conversational presence with balanced mid-range projection"
        ),
        VoiceCharacter(
            id: "expressive_presence",
            name: "Warm Expressive (Studio Master)",
            speakerEmbeddingFileName: "ses/studio-reference.pth",
            defaultTau: 0.25,
            defaultPitch: 0,
            description: "Natural vibrant timbre cloned directly from studio voice reference"
        ),
        VoiceCharacter(
            id: "spanish_warmth",
            name: "Spanish Warmth (Rich Harmonic)",
            speakerEmbeddingFileName: "ses/es.pth",
            defaultTau: 0.3,
            defaultPitch: 0,
            description: "Warm, rich acoustic timbre with natural expressive contour"
        ),
        VoiceCharacter(
            id: "french_elegance",
            name: "French Elegance (Refined Soft)",
            speakerEmbeddingFileName: "ses/fr.pth",
            defaultTau: 0.3,
            defaultPitch: 2,
            description: "Softened melodic vocal texture with delicate air"
        ),
        VoiceCharacter(
            id: "japanese_calm",
            name: "Japanese Serene (Clear)",
            speakerEmbeddingFileName: "ses/jp.pth",
            defaultTau: 0.3,
            defaultPitch: 1,
            description: "Clear, polite, and disciplined vocal delivery"
        ),
        VoiceCharacter(
            id: "soothing_meditation",
            name: "Whisper / Anti-Anxiety Soothe",
            speakerEmbeddingFileName: "ses/en-newest.pth",
            defaultTau: 0.2,
            defaultPitch: -2,
            description: "Softened breathy vocal tone for low-stimulation nervous system protection"
        ),
        VoiceCharacter(
            id: "deep_bass_presence",
            name: "Deep Sub-Bass (Resonant Chest)",
            speakerEmbeddingFileName: "ses/deep-bass.pth",
            defaultTau: 0.35,
            defaultPitch: -5,
            description: "Commanding deep chest resonance with low fundamental authority"
        ),
        VoiceCharacter(
            id: "velvet_alto",
            name: "Velvet Alto (Warm Intimate)",
            speakerEmbeddingFileName: "ses/velvet-alto.pth",
            defaultTau: 0.28,
            defaultPitch: -1,
            description: "Smooth, velvety close-mic vocal body with warm intimate presence"
        ),
        VoiceCharacter(
            id: "nordic_calm",
            name: "Nordic Serenity (Minimalist Clean)",
            speakerEmbeddingFileName: "ses/nordic-calm.pth",
            defaultTau: 0.3,
            defaultPitch: 0,
            description: "Crisp, balanced European clarity with pristine transparent mids"
        ),
        VoiceCharacter(
            id: "yoga_nidra",
            name: "Yoga Nidra (Hypnotic Breath)",
            speakerEmbeddingFileName: "ses/yoga-nidra.pth",
            defaultTau: 0.22,
            defaultPitch: -3,
            description: "Hypnotic, breath-supported meditation tone designed to reduce meeting stress"
        ),
        VoiceCharacter(
            id: "dynamic_presenter",
            name: "Dynamic Keynote (Confident Punch)",
            speakerEmbeddingFileName: "ses/en-style.pth",
            defaultTau: 0.35,
            defaultPitch: 1,
            description: "Forward-projecting, engaging keynote style for presentations"
        ),
        VoiceCharacter(
            id: "german_studio",
            name: "Precision Broadcast (German Studio)",
            speakerEmbeddingFileName: "ses/de-studio.pth",
            defaultTau: 0.3,
            defaultPitch: -2,
            description: "Structured, articulate broadcast cadence with crystal-clear diction"
        ),
        VoiceCharacter(
            id: "italian_lyric",
            name: "Italian Bel Canto (Warm Lyrical)",
            speakerEmbeddingFileName: "ses/it-lyric.pth",
            defaultTau: 0.32,
            defaultPitch: 0,
            description: "Harmonically rich, expressive vocal cadence with melodic warmth"
        ),
        VoiceCharacter(
            id: "british_rp",
            name: "British RP (Formal Articulate)",
            speakerEmbeddingFileName: "ses/en-br.pth",
            defaultTau: 0.3,
            defaultPitch: -2,
            description: "Classic Received Pronunciation with dignified, measured pacing"
        ),
        VoiceCharacter(
            id: "global_consultant",
            name: "Global Consultant (Melodic Clarity)",
            speakerEmbeddingFileName: "ses/en-india.pth",
            defaultTau: 0.3,
            defaultPitch: 0,
            description: "Engaging international consulting delivery with crisp melodic clarity"
        ),
        VoiceCharacter(
            id: "korean_studio",
            name: "K-Studio Vocal (Bright Air)",
            speakerEmbeddingFileName: "ses/kr.pth",
            defaultTau: 0.28,
            defaultPitch: 2,
            description: "Modern bright studio vocal profile with elevated harmonic sheen"
        ),
        VoiceCharacter(
            id: "mandarin_clarity",
            name: "Mandarin Precision (Crisp Diction)",
            speakerEmbeddingFileName: "ses/zh.pth",
            defaultTau: 0.3,
            defaultPitch: 1,
            description: "Tonal clarity with crisp consonant transients and neutral contour"
        ),
        VoiceCharacter(
            id: "cyber_harmonic",
            name: "Cyber Harmonic (Modern Resonant)",
            speakerEmbeddingFileName: "ses/cyber-harmonic.pth",
            defaultTau: 0.38,
            defaultPitch: -1,
            description: "Polished modern harmonic presence with tight digital resonance"
        )
    ]

    public static let builtinPresets: [VoicePreset] = [
        VoicePreset(id: "us_executive", name: "Executive", emoji: "🎙️", description: "Confident US executive presence with resonant lows", characterId: "american_executive", pitchShift: -2, indexRate: 0.3, isBuiltin: true),
        VoicePreset(id: "uk_authority", name: "Authority", emoji: "🏛️", description: "Calm British composure to de-escalate tension", characterId: "british_authority", pitchShift: -4, indexRate: 0.3, isBuiltin: true),
        VoicePreset(id: "warm_expressive", name: "Warm Studio", emoji: "✨", description: "Natural vibrant timbre cloned from reference", characterId: "expressive_presence", pitchShift: 0, indexRate: 0.25, isBuiltin: true),
        VoicePreset(id: "calm_negotiator", name: "Negotiator", emoji: "🤝", description: "Crisp presence with balanced mid projection", characterId: "australian_negotiator", pitchShift: 0, indexRate: 0.35, isBuiltin: true),
        VoicePreset(id: "soothing_whisper", name: "Anti-Anxiety", emoji: "🍃", description: "Softened breathy vocal tone for low stimulation", characterId: "soothing_meditation", pitchShift: -2, indexRate: 0.2, isBuiltin: true),
        VoicePreset(id: "deep_resonance", name: "Deep Sub-Bass", emoji: "🗿", description: "Commanding lowered baritone chest authority", characterId: "deep_bass_presence", pitchShift: -5, indexRate: 0.35, isBuiltin: true),
        VoicePreset(id: "velvet_warmth", name: "Velvet Alto", emoji: "🕯️", description: "Smooth, velvety close-mic vocal presence", characterId: "velvet_alto", pitchShift: -1, indexRate: 0.28, isBuiltin: true),
        VoicePreset(id: "nordic_clarity", name: "Nordic Calm", emoji: "❄️", description: "Clean, transparent European conference tone", characterId: "nordic_calm", pitchShift: 0, indexRate: 0.3, isBuiltin: true),
        VoicePreset(id: "meditation_calm", name: "Yoga Nidra", emoji: "🧘", description: "Hypnotic, breath-supported soothing tone", characterId: "yoga_nidra", pitchShift: -3, indexRate: 0.22, isBuiltin: true),
        VoicePreset(id: "keynote_punch", name: "Keynote Pro", emoji: "⚡", description: "Dynamic, forward-projecting presentation energy", characterId: "dynamic_presenter", pitchShift: 1, indexRate: 0.35, isBuiltin: true),
        VoicePreset(id: "spanish_warmth", name: "Spanish Warmth", emoji: "🌞", description: "Harmonic expressive contour with rich timbre", characterId: "spanish_warmth", pitchShift: 0, indexRate: 0.3, isBuiltin: true),
        VoicePreset(id: "french_elegance", name: "French Elegance", emoji: "🥐", description: "Refined melodic vocal texture with delicate air", characterId: "french_elegance", pitchShift: 2, indexRate: 0.3, isBuiltin: true),
        VoicePreset(id: "japanese_calm", name: "Japanese Serene", emoji: "🍵", description: "Clear, disciplined and articulate delivery", characterId: "japanese_calm", pitchShift: 1, indexRate: 0.3, isBuiltin: true),
        VoicePreset(id: "german_broadcast", name: "German Studio", emoji: "📻", description: "Structured broadcast precision and diction", characterId: "german_studio", pitchShift: -2, indexRate: 0.3, isBuiltin: true),
        VoicePreset(id: "italian_belcanto", name: "Italian Lyric", emoji: "🎭", description: "Warm lyrical contour with harmonic resonance", characterId: "italian_lyric", pitchShift: 0, indexRate: 0.32, isBuiltin: true),
        VoicePreset(id: "british_formal", name: "British RP", emoji: "👑", description: "Dignified classical BBC Received Pronunciation", characterId: "british_rp", pitchShift: -2, indexRate: 0.3, isBuiltin: true),
        VoicePreset(id: "global_advisor", name: "Global Advisor", emoji: "🌐", description: "Clear international cadence for consulting", characterId: "global_consultant", pitchShift: 0, indexRate: 0.3, isBuiltin: true),
        VoicePreset(id: "cyber_modern", name: "Cyber Presence", emoji: "🔮", description: "Modern polished resonance with tight sheen", characterId: "cyber_harmonic", pitchShift: -1, indexRate: 0.38, isBuiltin: true)
    ]

    @Published public var isRunning: Bool = false
    @Published public var isConverting: Bool = false
    @Published public var isNeuralModelLoaded: Bool = false {
        didSet {
            if !isNeuralModelLoaded {
                loadWeightsTask?.cancel()
                outputLevel = 0.0
            }
        }
    }
    public var loadWeightsTask: Task<Void, Never>? = nil
    @Published public var modelLoadStatus: ModelLoadStatus = .loading(character: "Initializing")
    @Published public var lastInferenceDurationMs: Double = 0.0
    @Published public var isSynthesizingChunk: Bool = false
    @Published public var testSynthesisStatus: String? = nil
    @Published public var loadedComponents: (hubert: Bool, rmvpe: Bool, synth: Bool, index: Bool) = (false, false, false, false)
    @Published public var downloadProgress: Double = 0.0
    @Published public var isDownloading: Bool = false
    @Published public var statusMessage: String = "Ready"
    @Published public var selectedCharacter: VoiceCharacter = availableCharacters[0] {
        didSet { loadCharacterWeights(character: selectedCharacter) }
    }
    
    // Device Routing
    @Published public var errorMessage: String? = nil
    @Published public var selectedInputDevice: AudioDeviceInfo? {
        didSet { applyDeviceRouting() }
    }
    @Published public var selectedOutputDevice: AudioDeviceInfo? {
        didSet { applyDeviceRouting() }
    }

    // Performance Sliders & Silence Gate
    public static let defaultSilenceThreshold: Float = 0.008 // ~ -42 dBFS (realistic speech gate; filters mic floor and room ambient noise)
    public static let absoluteSilenceFloor: Float = 0.0005 // Absolute safety floor: pure digital zeros and sub-audible ADC noise (< -66 dBFS) are NEVER synthesized even if threshold slider is 0.0

    @Published public var pitchShiftSemitones: Float = 0.0 {
        didSet { updatePerformanceControls() }
    }
    @Published public var toneColorTau: Float = 0.3 {
        didSet {
            if abs(indexRate - toneColorTau) > 0.001 {
                indexRate = toneColorTau
            }
            updatePerformanceControls()
        }
    }
    @Published public var indexRate: Float = 0.3 {
        didSet {
            if abs(toneColorTau - indexRate) > 0.001 {
                toneColorTau = indexRate
            }
            updatePerformanceControls()
        }
    }
    @Published public var silenceThreshold: Float = defaultSilenceThreshold {
        didSet { updatePerformanceControls() }
    }
    @Published public var isVoiceActive: Bool = false
    @Published public var inputLevel: Float = 0.0
    @Published public var rawInputRMS: Float = 0.0
    @Published public var outputLevel: Float = 0.0

    // MARK: - Voice Lab Presets (Built-in & Custom User Presets)
    @Published public var userPresets: [VoicePreset] = []
    @Published public var selectedPresetId: String? = "clean"

    // Audio Engine Nodes
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let pitchNode = AVAudioUnitTimePitch()
    private let eqNode = AVAudioUnitEQ(numberOfBands: 2)
    public private(set) var playbackFormat: AVAudioFormat?
    private var inputDeviceID: AudioDeviceID = 0
    private var inputIOProcID: AudioDeviceIOProcID?
    private let inputIOQueue = DispatchQueue(label: "com.rvc.input.io", qos: .userInteractive)
    private var systemTap: AnyObject?
    public var userStopped: Bool = false
    public var isTestMode: Bool = false
    public private(set) var isRestarting: Bool = false
    private var restartWorkItem: DispatchWorkItem?
    private var isConfiguringEngine: Bool = false
    private var configChangeObserver: NSObjectProtocol?

    // Startup settling & DC offset filter to eliminate power-on synthetic buzz
    private var startupDiscardFrames: Int = 0
    private var dcFilterX: Float = 0.0
    private var dcFilterY: Float = 0.0

    public func setInputDevice(_ device: AudioDeviceInfo, autoStartIfReady: Bool = true) {
        let wasActive = isRunning || isRestarting
        userStopped = false
        selectedInputDevice = device
        if !wasActive && !isRestarting && autoStartIfReady && selectedOutputDevice != nil {
            start()
        }
    }

    public func setOutputDevice(_ device: AudioDeviceInfo, autoStartIfReady: Bool = true) {
        let wasActive = isRunning || isRestarting
        userStopped = false
        selectedOutputDevice = device
        if !wasActive && !isRestarting && autoStartIfReady && selectedInputDevice != nil {
            start()
        }
    }

    private func applyDeviceRouting() {
        guard !isConfiguringEngine else { return }
        if isRunning || isRestarting {
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }
    }

    // Processing state
    private let rvcQueue = DispatchQueue(label: "com.rvc.processing.queue", qos: .userInteractive)
    public let rvcInference = RVCInference()

    // Low-latency chunk accumulation for OpenVoice V2 (5120 samples @ 22050Hz ≈ 0.232s = 20 STFT frames of hop 256)
    private var accumulatedSamples: [Float] = []
    public let targetChunkSamples: Int = 5120
    private var isProcessingChunk: Bool = false
    private var isPriorChunkActive: Bool = false
    private var currentInferenceTask: Task<Void, Never>? = nil

    private static let scratchCapacity = 16384
    private let monoInputScratch = UnsafeMutablePointer<Float>.allocate(capacity: AudioController.scratchCapacity)

    public init() {
        Self.configureMetalLibrary()
        setupEngine()
        setupConfigurationChangeObserver()
        loadUserPresets()
        loadCharacterWeights(character: selectedCharacter)
    }

    deinit {
        if let obs = configChangeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        engine.stop()
        monoInputScratch.deallocate()
    }

    private func setupConfigurationChangeObserver() {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isConfiguringEngine else { return }
                guard (self.isRunning || self.isRestarting) && !self.userStopped else { return }
                if !self.engine.isRunning {
                    self.applyDeviceRouting()
                }
            }
        }
    }

    public static func configureMetalLibrary() {
        if GPU.metallib != nil { return }
        
        let fileManager = FileManager.default
        var candidatePaths: [String] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidatePaths.append(resourceURL.appendingPathComponent("default.metallib").path)
            candidatePaths.append(resourceURL.appendingPathComponent("mlx.metallib").path)
            candidatePaths.append(resourceURL.appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib").path)
        }

        let execDir = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS").path
        candidatePaths.append("\(execDir)/default.metallib")
        candidatePaths.append("\(execDir)/mlx.metallib")
        candidatePaths.append("\(execDir)/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib")

        // Search relative to working directory or common build output directories
        candidatePaths.append(".build/out/Products/Release/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib")
        candidatePaths.append(".build/arm64-apple-macosx/release/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib")
        candidatePaths.append(".build/arm64-apple-macosx/debug/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib")

        for path in candidatePaths {
            if fileManager.fileExists(atPath: path) {
                print("==> Configured MLX Metal library from: \(path)")
                GPU.metallib = URL(fileURLWithPath: path)
                return
            }
        }
        print("Warning: Could not locate default.metallib among candidates.")
    }

    private func setupEngine() {
        engine.attach(playerNode)
        engine.attach(pitchNode)
        engine.attach(eqNode)

        let mainFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        let sampleRate = mainFormat.sampleRate > 0 ? mainFormat.sampleRate : 48000.0
        let channels: AVAudioChannelCount = max(1, min(2, mainFormat.channelCount))
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) ?? engine.mainMixerNode.outputFormat(forBus: 0)
        playbackFormat = format

        // Chain: playerNode -> pitchNode -> eqNode -> mainMixerNode
        engine.connect(playerNode, to: pitchNode, format: format)
        engine.connect(pitchNode, to: eqNode, format: format)
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)

        updatePerformanceControls()
    }

    public func updatePerformanceControls() {
        // Real-Time pitch shift: 1 semitone = 100 cents (OpenVoice ToneColorConverter preserves natural vocal pitch contour)
        pitchNode.pitch = pitchShiftSemitones * 100.0

        // Apply character-specific acoustic formant EQ filtering
        if eqNode.bands.count >= 2 {
            let band0 = eqNode.bands[0]
            let band1 = eqNode.bands[1]

            switch selectedCharacter.id {
            case "american_executive", "deep_bass_presence":
                // Resonant deep chest lows (+5.5dB @ 150Hz), controlled highs (-3.5dB @ 4.8kHz)
                band0.filterType = .lowShelf
                band0.frequency = (selectedCharacter.id == "deep_bass_presence") ? 120.0 : 160.0
                band0.gain = ((selectedCharacter.id == "deep_bass_presence") ? 6.5 : 5.0) * indexRate
                band0.bypass = false

                band1.filterType = .highShelf
                band1.frequency = 4800.0
                band1.gain = -3.5 * indexRate
                band1.bypass = false

            case "british_authority", "british_rp", "german_studio":
                // Calm BBC/studio authority: Warm lower-mids (+3.5dB @ 200Hz), smooth articulate highs (+2dB @ 5.5kHz)
                band0.filterType = .lowShelf
                band0.frequency = 200.0
                band0.gain = 3.5 * indexRate
                band0.bypass = false

                band1.filterType = .highShelf
                band1.frequency = 5500.0
                band1.gain = 2.0 * indexRate
                band1.bypass = false

            case "australian_negotiator", "dynamic_presenter", "global_consultant":
                // Forward conversational presence: Mid punch (+4dB @ 2.4kHz), air sparkle (+3dB @ 8kHz)
                band0.filterType = .parametric
                band0.frequency = 2400.0
                band0.bandwidth = 1.0
                band0.gain = 4.0 * indexRate
                band0.bypass = false

                band1.filterType = .highShelf
                band1.frequency = 8000.0
                band1.gain = 3.0 * indexRate
                band1.bypass = false

            case "soothing_meditation", "yoga_nidra":
                // ASMR / anti-anxiety nervous system soothe: High-pass rumble, soft velvety highs (-4dB @ 6.5kHz)
                band0.filterType = .highPass
                band0.frequency = 180.0
                band0.bypass = false

                band1.filterType = .highShelf
                band1.frequency = 6500.0
                band1.gain = -4.0 * indexRate
                band1.bypass = false

            case "velvet_alto", "nordic_calm", "french_elegance", "expressive_presence":
                // Intimate acoustic velvet: Gentle warm body (+2.5dB @ 240Hz), transparent airy top (+3.5dB @ 7.5kHz)
                band0.filterType = .parametric
                band0.frequency = 240.0
                band0.bandwidth = 1.2
                band0.gain = 2.5 * indexRate
                band0.bypass = false

                band1.filterType = .highShelf
                band1.frequency = 7500.0
                band1.gain = 3.5 * indexRate
                band1.bypass = false

            case "spanish_warmth", "italian_lyric":
                // Rich harmonic warmth: Lower-mid fullness (+3.8dB @ 280Hz), expressive treble (+2.8dB @ 5.2kHz)
                band0.filterType = .lowShelf
                band0.frequency = 280.0
                band0.gain = 3.8 * indexRate
                band0.bypass = false

                band1.filterType = .highShelf
                band1.frequency = 5200.0
                band1.gain = 2.8 * indexRate
                band1.bypass = false

            case "japanese_calm", "mandarin_clarity", "korean_studio":
                // Clear disciplined articulation: Tight low cut (140Hz), crisp consonant intelligibility (+4.5dB @ 3.6kHz)
                band0.filterType = .highPass
                band0.frequency = 140.0
                band0.bypass = false

                band1.filterType = .parametric
                band1.frequency = 3600.0
                band1.bandwidth = 1.0
                band1.gain = 4.5 * indexRate
                band1.bypass = false

            case "cyber_harmonic":
                // Modern cyber resonance: Mid clarity peak (+4dB @ 1.8kHz), brilliant sheen (+4dB @ 9kHz)
                band0.filterType = .parametric
                band0.frequency = 1800.0
                band0.bandwidth = 0.9
                band0.gain = 4.0 * indexRate
                band0.bypass = false

                band1.filterType = .highShelf
                band1.frequency = 9000.0
                band1.gain = 4.0 * indexRate
                band1.bypass = false

            default:
                band0.bypass = true
                band1.bypass = true
            }
        }
    }

    // MARK: - Voice Preset Management
    public func loadUserPresets() {
        if let data = UserDefaults.standard.data(forKey: "custom_voice_presets"),
           let decoded = try? JSONDecoder().decode([VoicePreset].self, from: data) {
            userPresets = decoded
        }
    }

    public func saveUserPreset(name: String, emoji: String = "⭐") {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let id = "user-" + UUID().uuidString.prefix(8).lowercased()
        let newPreset = VoicePreset(
            id: id,
            name: trimmedName,
            emoji: emoji.isEmpty ? "⭐" : String(emoji.prefix(2)),
            description: "Custom Voice Lab State",
            characterId: selectedCharacter.id,
            pitchShift: pitchShiftSemitones,
            indexRate: indexRate,
            silenceThreshold: silenceThreshold,
            isBuiltin: false
        )
        userPresets.append(newPreset)
        persistUserPresets()
        selectedPresetId = id
    }

    public func deleteUserPreset(id: String) {
        userPresets.removeAll { $0.id == id }
        persistUserPresets()
        if selectedPresetId == id {
            selectedPresetId = nil
        }
    }

    private func persistUserPresets() {
        if let encoded = try? JSONEncoder().encode(userPresets) {
            UserDefaults.standard.set(encoded, forKey: "custom_voice_presets")
        }
    }

    public func applyPreset(_ preset: VoicePreset) {
        selectedPresetId = preset.id
        if let char = Self.availableCharacters.first(where: { $0.id == preset.characterId }) {
            if selectedCharacter.id != char.id {
                selectedCharacter = char
            }
        }
        pitchShiftSemitones = preset.pitchShift
        indexRate = preset.indexRate
        silenceThreshold = preset.silenceThreshold
        updatePerformanceControls()
    }

    public func checkModelFiles(character: VoiceCharacter) -> (hasModel: Bool, hasHubert: Bool, hasRMVPE: Bool, hasIndex: Bool, missing: [String]) {
        let fileManager = FileManager.default
        let modelsDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("OpenVoiceModels") ?? URL(fileURLWithPath: "/tmp/OpenVoiceModels")
        
        let ckptURL = modelsDir.appendingPathComponent("checkpoint.pth")
        let configURL = modelsDir.appendingPathComponent("config.json")
        let seURL = modelsDir.appendingPathComponent(character.speakerEmbeddingFileName)
        
        var missing: [String] = []
        let hasCkpt = fileManager.fileExists(atPath: ckptURL.path) && ((try? fileManager.attributesOfItem(atPath: ckptURL.path)[.size] as? Int64) ?? 0) > 10_000_000
        if !hasCkpt { missing.append("checkpoint.pth") }
        
        let hasConfig = fileManager.fileExists(atPath: configURL.path)
        if !hasConfig { missing.append("config.json") }
        
        let hasSE = fileManager.fileExists(atPath: seURL.path)
        if !hasSE { missing.append(character.speakerEmbeddingFileName) }
        
        return (hasModel: hasCkpt, hasHubert: hasConfig, hasRMVPE: hasSE, hasIndex: true, missing: missing)
    }

    public func loadCharacterWeights(character: VoiceCharacter) {
        loadWeightsTask?.cancel()
        pitchShiftSemitones = Float(character.defaultPitch)
        toneColorTau = character.defaultTau
        updatePerformanceControls()

        let check = checkModelFiles(character: character)
        self.loadedComponents = (hubert: check.hasHubert, rmvpe: check.hasRMVPE, synth: check.hasModel, index: check.hasIndex)

        if !check.missing.isEmpty {
            self.isNeuralModelLoaded = false
            self.modelLoadStatus = .missing(files: check.missing)
            self.statusMessage = "Missing weights: \(check.missing.joined(separator: ", ")) — Audio Muted"
            return
        }

        self.modelLoadStatus = .loading(character: character.name)
        self.statusMessage = "Loading weights for \(character.name)..."

        loadWeightsTask = Task { [weak self] in
            let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("OpenVoiceModels") ?? URL(fileURLWithPath: "/tmp/OpenVoiceModels")
            let seURL = modelsDir.appendingPathComponent(character.speakerEmbeddingFileName)

            do {
                let startTime = CFAbsoluteTimeGetCurrent()
                guard let self = self, !Task.isCancelled else { return }

                guard FileManager.default.fileExists(atPath: seURL.path) else {
                    throw NSError(domain: "OpenVoice", code: 404, userInfo: [NSLocalizedDescriptionKey: "Voice profile \(character.speakerEmbeddingFileName) not found."])
                }

                await OpenVoiceBridge.shared.setTargetVoice(path: seURL.path)
                await OpenVoiceBridge.shared.setTau(tau: self.toneColorTau)
                
                let loadDurationMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

                await MainActor.run {
                    guard !Task.isCancelled else { return }
                    self.isNeuralModelLoaded = true
                    self.loadedComponents = (hubert: true, rmvpe: true, synth: true, index: true)
                    self.modelLoadStatus = .ready(character: character.name, hasIndex: true, latencyMs: loadDurationMs)
                    self.statusMessage = "OpenVoice V2 Active: \(character.name)"
                    self.updatePerformanceControls()
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.isNeuralModelLoaded = false
                    self.loadedComponents = (hubert: false, rmvpe: false, synth: false, index: false)
                    self.modelLoadStatus = .failed(error: error.localizedDescription)
                    self.statusMessage = "Model failed to load: \(error.localizedDescription) — Audio Muted"
                    self.updatePerformanceControls()
                }
            }
        }
    }

    public func testNeuralSynthesis() {
        guard isNeuralModelLoaded else {
            testSynthesisStatus = "Cannot test: Neural model is not loaded"
            return
        }

        testSynthesisStatus = "Testing synthesis..."
        Task {
            do {
                // Generate 0.5s harmonic tone test chunk (11025 samples @ 22050Hz)
                var testAudio = [Float](repeating: 0, count: 11025)
                for i in 0..<11025 {
                    let t = Float(i) / 22050.0
                    testAudio[i] = 0.3 * sin(2.0 * .pi * 220.0 * t) + 0.15 * sin(2.0 * .pi * 440.0 * t)
                }

                let start = CFAbsoluteTimeGetCurrent()
                let synth = try await OpenVoiceBridge.shared.convertChunk(samples: testAudio, tau: toneColorTau)
                let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000

                schedulePlayback(samples: synth, sampleRate: OpenVoiceBridge.shared.modelSampleRate)

                self.testSynthesisStatus = "✅ Working! Converted in \(Int(duration))ms (\(synth.count) samples played)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    if self.testSynthesisStatus?.starts(with: "✅") == true {
                        self.testSynthesisStatus = nil
                    }
                }
            } catch {
                self.testSynthesisStatus = "❌ Test failed: \(error.localizedDescription)"
            }
        }
    }

    private var downloadTask: Task<Void, Never>? = nil

    public func cancelDownload() {
        guard isDownloading else { return }
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        statusMessage = "Download cancelled by user."
        downloadProgress = 0.0
        let check = checkModelFiles(character: selectedCharacter)
        if check.missing.isEmpty && isNeuralModelLoaded {
            modelLoadStatus = .ready(character: selectedCharacter.name, hasIndex: check.hasIndex, latencyMs: 0)
        } else {
            modelLoadStatus = .missing(files: check.missing)
        }
    }

    public func downloadNeuralWeights() {
        guard !isDownloading else { return }
        isDownloading = true
        downloadProgress = 0.0
        statusMessage = "Connecting to Hugging Face..."
        modelLoadStatus = .downloading(progress: 0.0, fileName: "Connecting to Hugging Face...")

        downloadTask = Task {
            let fileManager = FileManager.default
            let modelsDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("OpenVoiceModels") ?? URL(fileURLWithPath: "/tmp/OpenVoiceModels")
            let sesDir = modelsDir.appendingPathComponent("ses")
            
            do {
                try fileManager.createDirectory(at: sesDir, withIntermediateDirectories: true)

                // Dedicated URLSession with request timeout to prevent indefinite stalling
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 25.0
                config.timeoutIntervalForResource = 900.0
                config.waitsForConnectivity = true
                let session = URLSession(configuration: config)

                let downloads: [(name: String, path: URL, urlString: String, weight: Double)] = [
                    (
                        name: "OpenVoice V2 ToneColor Checkpoint",
                        path: modelsDir.appendingPathComponent("checkpoint.pth"),
                        urlString: "https://huggingface.co/myshell-ai/OpenVoiceV2/resolve/main/converter/checkpoint.pth",
                        weight: 0.85
                    ),
                    (
                        name: "OpenVoice Config",
                        path: modelsDir.appendingPathComponent("config.json"),
                        urlString: "https://huggingface.co/myshell-ai/OpenVoiceV2/raw/main/converter/config.json",
                        weight: 0.05
                    ),
                    (
                        name: "US English Voice Profile",
                        path: sesDir.appendingPathComponent("en-us.pth"),
                        urlString: "https://huggingface.co/myshell-ai/OpenVoiceV2/resolve/main/base_speakers/ses/en-us.pth",
                        weight: 0.05
                    ),
                    (
                        name: "British English Voice Profile",
                        path: sesDir.appendingPathComponent("en-default.pth"),
                        urlString: "https://huggingface.co/myshell-ai/OpenVoiceV2/resolve/main/base_speakers/ses/en-default.pth",
                        weight: 0.05
                    )
                ]

                var completedWeight: Double = 0.0

                for item in downloads {
                    if Task.isCancelled { break }

                    if fileManager.fileExists(atPath: item.path.path),
                       let attrs = try? fileManager.attributesOfItem(atPath: item.path.path),
                       let size = attrs[.size] as? Int64, size > 1_000 {
                        // Already downloaded and valid
                        completedWeight += item.weight
                        self.downloadProgress = completedWeight
                        self.modelLoadStatus = .downloading(progress: completedWeight, fileName: item.name)
                        continue
                    }

                    self.statusMessage = "Downloading \(item.name)..."
                    self.modelLoadStatus = .downloading(progress: completedWeight, fileName: item.name)
                    guard let remoteURL = URL(string: item.urlString) else { continue }

                    let (tempLocation, response) = try await session.download(from: remoteURL)
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
                        throw NSError(domain: "OpenVoiceDownload", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned HTTP \(httpResponse.statusCode)"])
                    }

                    if Task.isCancelled {
                        try? fileManager.removeItem(at: tempLocation)
                        break
                    }

                    if fileManager.fileExists(atPath: item.path.path) {
                        try? fileManager.removeItem(at: item.path)
                    }
                    try fileManager.moveItem(at: tempLocation, to: item.path)

                    completedWeight += item.weight
                    self.downloadProgress = min(1.0, completedWeight)
                    self.modelLoadStatus = .downloading(progress: min(1.0, completedWeight), fileName: item.name)
                }

                if Task.isCancelled {
                    self.isDownloading = false
                    self.statusMessage = "Download cancelled."
                    let check = self.checkModelFiles(character: self.selectedCharacter)
                    self.modelLoadStatus = check.missing.isEmpty ? .ready(character: self.selectedCharacter.name, hasIndex: check.hasIndex, latencyMs: 0) : .missing(files: check.missing)
                    return
                }

                self.downloadProgress = 1.0
                self.isDownloading = false
                self.statusMessage = "All neural models downloaded & ready!"
                self.loadCharacterWeights(character: self.selectedCharacter)
            } catch {
                self.isDownloading = false
                self.statusMessage = "Download failed: \(error.localizedDescription)"
                self.modelLoadStatus = .failed(error: error.localizedDescription)
            }
        }
    }

    // MARK: - Synchronous Hardware Device Auto-Resolution Helpers

    public static func isBluetoothDevice(id: AudioDeviceID) -> Bool {
        var transAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transType: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectGetPropertyData(id, &transAddr, 0, nil, &size, &transType) == noErr {
            return transType == kAudioDeviceTransportTypeBluetooth || transType == kAudioDeviceTransportTypeBluetoothLE
        }
        return false
    }

    public static func isBluetooth(device: AudioDeviceInfo) -> Bool {
        if device.isBluetooth { return true }
        if isBluetoothDevice(id: device.id) { return true }
        let lower = device.name.lowercased()
        return lower.contains("poly") || lower.contains("airpod") || lower.contains("headphone") || lower.contains("buds") || lower.contains("bluetooth")
    }

    public static func getDefaultHardwareDevice(isInput: Bool) -> AudioDeviceInfo? {
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

        guard let name = getDeviceStringProperty(id: deviceID, selector: kAudioObjectPropertyName),
              let uid = getDeviceStringProperty(id: deviceID, selector: kAudioDevicePropertyDeviceUID) else {
            return nil
        }

        let isBT = isBluetoothDevice(id: deviceID)
        return AudioDeviceInfo(
            id: deviceID,
            uid: uid,
            name: name,
            isInput: isInput,
            isOutput: !isInput,
            isBluetooth: isBT
        )
    }

    private static func getDeviceStringProperty(id: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var unmanagedStr: Unmanaged<CFString>? = nil
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &unmanagedStr) { ptr in
            AudioObjectGetPropertyData(id, &propertyAddress, 0, nil, &dataSize, ptr)
        }
        guard status == noErr, let cfStr = unmanagedStr?.takeRetainedValue() else { return nil }
        return cfStr as String
    }

    public static func getPhysicalMicrophone() -> AudioDeviceInfo? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return getDefaultHardwareDevice(isInput: true) }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return getDefaultHardwareDevice(isInput: true)
        }

        var candidateMic: AudioDeviceInfo?

        for id in deviceIDs {
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &streamAddr, 0, nil, &streamSize)
            guard streamSize > 0 else { continue }

            guard let name = getDeviceStringProperty(id: id, selector: kAudioObjectPropertyName),
                  let uid = getDeviceStringProperty(id: id, selector: kAudioDevicePropertyDeviceUID) else {
                continue
            }

            let lower = name.lowercased()
            if lower.contains("blackhole") || lower.contains("teams") || lower.contains("zoom") || lower.contains("loopback") {
                continue
            }

            let isBT = isBluetoothDevice(id: id)
            let info = AudioDeviceInfo(id: id, uid: uid, name: name, isInput: true, isOutput: false, isBluetooth: isBT)
            if uid == "BuiltInMicrophoneDevice" || lower.contains("built-in") || lower.contains("macbook pro microphone") {
                return info
            }
            if !isBT && candidateMic == nil {
                candidateMic = info
            }
        }

        return candidateMic ?? getDefaultHardwareDevice(isInput: true)
    }

    public static func getPhysicalSpeakers() -> AudioDeviceInfo? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return getDefaultHardwareDevice(isInput: false) }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr else {
            return getDefaultHardwareDevice(isInput: false)
        }

        var candidateSpeaker: AudioDeviceInfo?

        for id in deviceIDs {
            var streamAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &streamAddr, 0, nil, &streamSize)
            guard streamSize > 0 else { continue }

            guard let name = getDeviceStringProperty(id: id, selector: kAudioObjectPropertyName),
                  let uid = getDeviceStringProperty(id: id, selector: kAudioDevicePropertyDeviceUID) else {
                continue
            }

            let lower = name.lowercased()
            if lower.contains("blackhole") || lower.contains("teams") || lower.contains("zoom") || lower.contains("loopback") {
                continue
            }

            let isBT = isBluetoothDevice(id: id)
            let info = AudioDeviceInfo(id: id, uid: uid, name: name, isInput: false, isOutput: true, isBluetooth: isBT)
            if isBT || lower.contains("headphone") || lower.contains("airpod") || lower.contains("poly") {
                return info
            }
            if uid == "BuiltInSpeakerDevice" || lower.contains("speaker") {
                candidateSpeaker = info
            } else if candidateSpeaker == nil {
                candidateSpeaker = info
            }
        }

        return candidateSpeaker ?? getDefaultHardwareDevice(isInput: false)
    }

    public func handleIncomingAudioForTest(samples: [Float], fromRate: Double, isHardwareStartup: Bool = false) {
        if !isHardwareStartup {
            self.startupDiscardFrames = 0
        }
        samples.withUnsafeBufferPointer { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            self.handleIncomingAudio(channelData: baseAddress, frameCount: samples.count, fromRate: fromRate)
        }
    }

    public func start() {
        guard !isRunning && !isRestarting else { return }
        isConfiguringEngine = true
        defer { isConfiguringEngine = false }
        errorMessage = nil
        userStopped = false
        Self.configureMetalLibrary()
        accumulatedSamples.removeAll(keepingCapacity: true)
        currentInferenceTask?.cancel()
        currentInferenceTask = nil
        isProcessingChunk = false
        playerNode.stop()
        playerNode.reset()

        // 1. Auto-resolve hardware output destination if none selected
        let outDev: AudioDeviceInfo
        if let currentOut = selectedOutputDevice {
            outDev = currentOut
        } else if let autoOut = Self.getPhysicalSpeakers() {
            outDev = autoOut
            self.selectedOutputDevice = autoOut
        } else {
            let msg = "No audio output destination available on system."
            statusMessage = msg
            errorMessage = msg
            return
        }

        // 1. Configure playback engine for the selected output device (Bluetooth, Speakers, etc.)
        engine.stop()
        guard let outUnit = engine.outputNode.audioUnit else {
            let msg = "Audio output unit is not initialized."
            statusMessage = msg
            errorMessage = msg
            return
        }

        var devID = AppAudioEngine.liveDeviceID(for: outDev.uid, fallbackID: outDev.id)
        let setDevStatus = AudioUnitSetProperty(
            outUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &devID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        if setDevStatus != noErr {
            // If the selected output device rejects attachment (e.g. Bluetooth headset asleep / 1852797029 format error),
            // fallback to default hardware speakers so audio engine continues smoothly.
            if let fallback = Self.getPhysicalSpeakers() ?? Self.getDefaultHardwareDevice(isInput: false), fallback.id != devID {
                var fallbackID = fallback.id
                let fallbackStatus = AudioUnitSetProperty(
                    outUnit,
                    kAudioOutputUnitProperty_CurrentDevice,
                    kAudioUnitScope_Global,
                    0,
                    &fallbackID,
                    UInt32(MemoryLayout<AudioDeviceID>.size)
                )
                if fallbackStatus == noErr {
                    print("Notice: Output \(outDev.name) rejected assignment (\(setDevStatus)). Fell back to \(fallback.name).")
                    self.selectedOutputDevice = fallback
                    devID = fallbackID
                } else {
                    let msg = "Could not attach to audio destination \(outDev.name) (Status: \(setDevStatus))"
                    statusMessage = msg
                    errorMessage = msg
                    return
                }
            } else {
                let msg = "Could not attach to audio destination \(outDev.name) (Status: \(setDevStatus))"
                statusMessage = msg
                errorMessage = msg
                return
            }
        }

        // Query the actual hardware format of the output device (e.g. 44100Hz on Bluetooth, 48000Hz on Speakers)
        let outHWFormat = engine.outputNode.outputFormat(forBus: 0)
        let outRate = outHWFormat.sampleRate > 0 ? outHWFormat.sampleRate : 48000.0
        let channels: AVAudioChannelCount = max(1, min(2, outHWFormat.channelCount))
        guard let activeFormat = AVAudioFormat(standardFormatWithSampleRate: outRate, channels: channels) else {
            let msg = "Failed to create audio format for \(outDev.name) at \(outRate)Hz."
            statusMessage = msg
            errorMessage = msg
            return
        }
        self.playbackFormat = activeFormat

        // Reconnect audio graph matching the selected output device's hardware sample rate
        engine.disconnectNodeOutput(playerNode)
        engine.disconnectNodeOutput(pitchNode)
        engine.disconnectNodeOutput(eqNode)
        engine.disconnectNodeOutput(engine.mainMixerNode)

        engine.connect(playerNode, to: pitchNode, format: activeFormat)
        engine.connect(pitchNode, to: eqNode, format: activeFormat)
        engine.connect(eqNode, to: engine.mainMixerNode, format: activeFormat)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: outHWFormat)

        updatePerformanceControls()
        engine.prepare()

        do {
            try engine.start()
            playerNode.play()
        } catch {
            let msg = "Failed to start audio playback on \(outDev.name): \(error.localizedDescription)"
            statusMessage = msg
            errorMessage = msg
            return
        }

        // 2. Auto-resolve hardware microphone if none selected
        var inDev: AudioDeviceInfo
        if let currentIn = selectedInputDevice {
            inDev = currentIn
        } else if let autoMic = Self.getPhysicalMicrophone() {
            inDev = autoMic
            self.selectedInputDevice = autoMic
        } else {
            let msg = "No microphone / audio input source available on system."
            statusMessage = msg
            errorMessage = msg
            return
        }

        // If output is Bluetooth Headphones, avoid using Bluetooth mic as input (macOS downgrades Bluetooth to 16kHz SCO mono)
        let outIsBluetooth = Self.isBluetooth(device: outDev)
        let inIsBluetooth = Self.isBluetooth(device: inDev)
        if outIsBluetooth && inIsBluetooth {
            if let physicalMic = Self.getPhysicalMicrophone(), !Self.isBluetooth(device: physicalMic) {
                print("==> Auto-routed input to \(physicalMic.name) to preserve full A2DP stereo quality on \(outDev.name)")
                inDev = physicalMic
                self.selectedInputDevice = physicalMic
            }
        }

        var captureStarted = false

        if inDev.isSystemAudio {
            if #available(macOS 14.2, *) {
                let tap = SystemAudioTap()
                do {
                    try tap.prepare(clockDeviceUID: outDev.uid, targetDeviceUID: inDev.targetHardwareUID)
                    try tap.start { [weak self] l, r, frames in
                        guard let self = self, frames > 0 else { return }
                        self.handleIncomingAudio(channelData: l, frameCount: frames, fromRate: tap.sampleRate)
                    }
                    systemTap = tap
                    captureStarted = true
                } catch {
                    print("Warning: System Audio tap failed (\(error.localizedDescription)). Falling back to physical microphone.")
                    if let fallbackMic = Self.getPhysicalMicrophone() {
                        inDev = fallbackMic
                        self.selectedInputDevice = fallbackMic
                    }
                }
            }
        }

        if !captureStarted {
            let liveInID = AppAudioEngine.liveDeviceID(for: inDev.uid, fallbackID: inDev.id)
            var rateAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyNominalSampleRate,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var rate: Float64 = 48000.0
            var rateSize = UInt32(MemoryLayout<Float64>.size)
            AudioObjectGetPropertyData(liveInID, &rateAddr, 0, nil, &rateSize, &rate)
            let inSampleRate = rate > 0 ? rate : 48000.0

            // Initialize startup settling grace period (discard first 200ms of hardware settling transients)
            startupDiscardFrames = Int(inSampleRate * 0.20)
            dcFilterX = 0.0
            dcFilterY = 0.0

            if !isTestMode {
                var procID: AudioDeviceIOProcID?
                let status = AudioDeviceCreateIOProcIDWithBlock(&procID, liveInID, inputIOQueue) { [weak self] _, inInputData, _, _, _ in
                    guard let self = self else { return }
                    let abl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
                    guard abl.count > 0 else { return }

                    let scratch = self.monoInputScratch
                    let scratchCap = Self.scratchCapacity

                    if abl.count > 1,
                       let b0 = abl[0].mData?.assumingMemoryBound(to: Float.self),
                       let b1 = abl[1].mData?.assumingMemoryBound(to: Float.self) {
                        let f = min(scratchCap, Int(abl[0].mDataByteSize) / MemoryLayout<Float>.size)
                        for i in 0..<f {
                            scratch[i] = (b0[i] + b1[i]) * 0.5
                        }
                        self.handleIncomingAudio(channelData: scratch, frameCount: f, fromRate: inSampleRate)
                    } else if let b0 = abl[0].mData?.assumingMemoryBound(to: Float.self) {
                        let channels = max(1, Int(abl[0].mNumberChannels))
                        let totalFrames = Int(abl[0].mDataByteSize) / (MemoryLayout<Float>.size * channels)
                        guard totalFrames > 0 else { return }

                        if channels == 1 {
                            self.handleIncomingAudio(channelData: b0, frameCount: totalFrames, fromRate: inSampleRate)
                        } else {
                            let f = min(totalFrames, scratchCap)
                            for i in 0..<f {
                                scratch[i] = (b0[i * channels] + b0[i * channels + 1]) * 0.5
                            }
                            self.handleIncomingAudio(channelData: scratch, frameCount: f, fromRate: inSampleRate)
                        }
                    }
                }

                guard status == noErr, let p = procID else {
                    let msg = "Failed to start capture on \(inDev.name) (Status: \(status))"
                    statusMessage = msg
                    errorMessage = msg
                    return
                }

                inputDeviceID = liveInID
                inputIOProcID = p
                let startErr = AudioDeviceStart(liveInID, p)
                if startErr != noErr {
                    let msg = "Failed to activate audio hardware \(inDev.name) (Status: \(startErr))"
                    statusMessage = msg
                    errorMessage = msg
                    return
                }
            }
            captureStarted = true
        }

        isRunning = true
        isConverting = true
        isVoiceActive = false
        rawInputRMS = 0.0
        inputLevel = 0.0
        outputLevel = 0.0
        errorMessage = nil
        if isNeuralModelLoaded {
            statusMessage = "OpenVoice V2 Active: \(selectedCharacter.name)"
        } else {
            statusMessage = "Model weights not downloaded — Audio muted"
        }
    }

    private func handleIncomingAudio(channelData: UnsafePointer<Float>, frameCount: Int, fromRate: Double) {
        // 1. Startup settling: Discard initial hardware power-on transients to prevent synthetic noise burst on start
        var activeChannelData = channelData
        var activeCount = frameCount

        if startupDiscardFrames > 0 {
            let discard = min(activeCount, startupDiscardFrames)
            startupDiscardFrames -= discard
            for i in 0..<discard {
                let x = activeChannelData[i]
                let y = x - dcFilterX + 0.995 * dcFilterY
                dcFilterX = x
                dcFilterY = y
            }
            activeChannelData = activeChannelData.advanced(by: discard)
            activeCount -= discard
            if activeCount <= 0 { return }
        }

        // 2. DC Blocker & Low-Frequency Sub-audible rumble filter (removes DC bias from microphone)
        var filteredData = [Float](repeating: 0, count: activeCount)
        for i in 0..<activeCount {
            let x = activeChannelData[i]
            let y = x - dcFilterX + 0.995 * dcFilterY
            dcFilterX = x
            dcFilterY = y
            filteredData[i] = y
        }

        // 3. Measure clean AC RMS without DC bias
        var rms: Float = 0
        vDSP_rmsqv(filteredData, 1, &rms, vDSP_Length(activeCount))
        DispatchQueue.main.async {
            self.inputLevel = min(1.0, max(0.0, rms * 4.0))
            self.rawInputRMS = rms
        }

        let resampled = filteredData.withUnsafeBufferPointer { ptr -> [Float] in
            guard let base = ptr.baseAddress else { return [] }
            return self.resample(samples: Array(UnsafeBufferPointer(start: base, count: activeCount)), fromRate: fromRate, toRate: OpenVoiceBridge.shared.modelSampleRate)
        }

        Task { @MainActor in
            guard self.isRunning else { return }
            self.accumulatedSamples.append(contentsOf: resampled)
            self.processNextChunkIfAvailable()
        }
    }

    @MainActor
    private func processNextChunkIfAvailable() {
        guard isRunning && !isProcessingChunk else { return }

        // Drop backlog if accumulated samples exceed 2 chunks to avoid latency buildup
        if accumulatedSamples.count > targetChunkSamples * 2 {
            accumulatedSamples.removeFirst(accumulatedSamples.count - targetChunkSamples * 2)
        }

        guard accumulatedSamples.count >= targetChunkSamples else { return }

        let chunkToProcess = Array(accumulatedSamples.prefix(targetChunkSamples))
        accumulatedSamples.removeFirst(targetChunkSamples)

        var chunkRms: Float = 0
        vDSP_rmsqv(chunkToProcess, 1, &chunkRms, vDSP_Length(chunkToProcess.count))

        let effectiveThreshold = max(Self.absoluteSilenceFloor, silenceThreshold)
        let isSilent = chunkRms < effectiveThreshold

        if isSilent {
            isVoiceActive = false
            outputLevel = 0.0
            currentInferenceTask?.cancel()
            currentInferenceTask = nil
            isProcessingChunk = false
            accumulatedSamples.removeAll(keepingCapacity: true)
            if isPriorChunkActive {
                isPriorChunkActive = false
                Task { await OpenVoiceBridge.shared.resetContext() }
            }
            if playerNode.isPlaying {
                playerNode.stop()
                playerNode.reset()
            }
        } else {
            isVoiceActive = true
            processAudioChunk(chunk22k: chunkToProcess)
        }
    }

    public func stop(preserveRestarting: Bool = false) {
        if !preserveRestarting {
            restartWorkItem?.cancel()
            restartWorkItem = nil
            isRestarting = false
        }
        guard isRunning || engine.isRunning || systemTap != nil || inputIOProcID != nil else { return }
        currentInferenceTask?.cancel()
        currentInferenceTask = nil
        isProcessingChunk = false
        isPriorChunkActive = false
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
        playerNode.stop()
        playerNode.reset()
        engine.stop()
        accumulatedSamples.removeAll(keepingCapacity: false)
        isRunning = false
        isConverting = false
        isVoiceActive = false
        statusMessage = "Stopped"
        inputLevel = 0.0
        rawInputRMS = 0.0
        outputLevel = 0.0
    }

    // MARK: - OpenVoice Audio Processing

    public func processAudioChunk(chunk22k: [Float]) {
        guard !chunk22k.isEmpty else { return }

        // If model is not loaded, strictly mute output and return immediately
        guard self.isNeuralModelLoaded else {
            self.outputLevel = 0.0
            self.isVoiceActive = false
            return
        }

        var chunkRms: Float = 0
        vDSP_rmsqv(chunk22k, 1, &chunkRms, vDSP_Length(chunk22k.count))

        // Effective gate threshold: always enforce absoluteSilenceFloor even if silenceThreshold slider is 0.0
        let effectiveThreshold = max(Self.absoluteSilenceFloor, self.silenceThreshold)
        guard chunkRms >= effectiveThreshold else {
            self.isVoiceActive = false
            self.outputLevel = 0.0
            self.currentInferenceTask?.cancel()
            self.currentInferenceTask = nil
            self.isProcessingChunk = false
            if self.isPriorChunkActive {
                self.isPriorChunkActive = false
                Task { await OpenVoiceBridge.shared.resetContext() }
            }
            return
        }

        self.isVoiceActive = true
        self.isProcessingChunk = true
        self.isSynthesizingChunk = true

        let currentTau = self.toneColorTau

        currentInferenceTask?.cancel()
        currentInferenceTask = Task {
            let start = CFAbsoluteTimeGetCurrent()
            do {
                guard !Task.isCancelled,
                      self.isRunning,
                      self.isVoiceActive,
                      self.isNeuralModelLoaded else {
                    self.outputLevel = 0.0
                    self.isSynthesizingChunk = false
                    self.isProcessingChunk = false
                    self.processNextChunkIfAvailable()
                    return
                }

                // Voice conversion via OpenVoice V2 Tone Color Converter
                let convertedSamples = try await OpenVoiceBridge.shared.convertChunk(
                    samples: chunk22k,
                    tau: currentTau
                )

                guard !Task.isCancelled, self.isRunning, self.isVoiceActive else {
                    self.outputLevel = 0.0
                    self.isSynthesizingChunk = false
                    self.isProcessingChunk = false
                    self.processNextChunkIfAvailable()
                    return
                }

                var processed = convertedSamples
                // Smooth fade-in only when transitioning from silence to active speech
                if !self.isPriorChunkActive {
                    self.applyFadeIn(samples: &processed, rampLength: 48)
                    self.isPriorChunkActive = true
                }

                // Schedule playback at OpenVoice 22,050 Hz
                self.schedulePlayback(samples: processed, sampleRate: OpenVoiceBridge.shared.modelSampleRate)

                let duration = (CFAbsoluteTimeGetCurrent() - start) * 1000
                self.lastInferenceDurationMs = duration
                self.isSynthesizingChunk = false
            } catch {
                if !Task.isCancelled {
                    print("OpenVoice Processing error: \(error)")
                }
                self.outputLevel = 0.0
                self.isSynthesizingChunk = false
            }

            self.isProcessingChunk = false
            self.processNextChunkIfAvailable()
        }
    }

    public func processAudioChunk(chunk16k: [Float]) {
        let chunk22k = self.resample(samples: chunk16k, fromRate: 16000.0, toRate: OpenVoiceBridge.shared.modelSampleRate)
        processAudioChunk(chunk22k: chunk22k)
    }

    private func applyFadeIn(samples: inout [Float], rampLength: Int = 48) {
        let n = samples.count
        let len = min(rampLength, n)
        guard len > 0 else { return }
        for i in 0..<len {
            let factor = 0.5 * (1.0 - cos(Float.pi * Float(i) / Float(len)))
            samples[i] *= factor
        }
    }

    public func schedulePlayback(samples: [Float], sampleRate: Double) {
        guard !samples.isEmpty else { return }

        // Use the connection format of playerNode so AVAudioPlayerNode never throws format mismatch exception
        guard let pFormat = playbackFormat ?? AVAudioFormat(standardFormatWithSampleRate: 48000.0, channels: 2) else {
            return
        }

        let targetRate = pFormat.sampleRate
        let channelCount = Int(pFormat.channelCount)

        // Resample from MLX output sampleRate to the player node's sample rate if needed
        var resampled: [Float]
        if abs(sampleRate - targetRate) < 1.0 {
            resampled = samples
        } else {
            resampled = resample(samples: samples, fromRate: sampleRate, toRate: targetRate)
        }

        let frameCount = AVAudioFrameCount(resampled.count)
        guard frameCount > 0,
              let pcmBuffer = AVAudioPCMBuffer(pcmFormat: pFormat, frameCapacity: frameCount) else {
            return
        }

        pcmBuffer.frameLength = frameCount
        if let channelData = pcmBuffer.floatChannelData {
            for ch in 0..<channelCount {
                channelData[ch].initialize(from: resampled, count: resampled.count)
            }
        }

        // Measure output RMS
        var rms: Float = 0
        vDSP_rmsqv(resampled, 1, &rms, vDSP_Length(resampled.count))

        guard rms >= Self.absoluteSilenceFloor else {
            self.outputLevel = 0.0
            return
        }

        self.outputLevel = min(1.0, max(0.0, rms * 4.0))

        playerNode.scheduleBuffer(pcmBuffer, at: nil, options: [])
        if !playerNode.isPlaying && isRunning {
            playerNode.play()
        }
    }

    // MARK: - High-Resolution Anti-Aliased Resampling & Spectral Bandwidth Extension

    /// High-resolution sample rate converter using 4-point Hermite cubic spline interpolation,
    /// 2-pole Butterworth low-pass anti-aliasing filter on downsampling, and harmonic bandwidth extension on 48kHz output.
    private func resample(samples: [Float], fromRate: Double, toRate: Double) -> [Float] {
        if abs(fromRate - toRate) < 1.0 || samples.isEmpty {
            return samples
        }

        var sourceSamples = samples

        // 1. Anti-aliasing low-pass filter if downsampling (e.g. 48kHz -> 22.05kHz)
        // Cutoff set safely at 0.46 of toRate (e.g. ~10.14 kHz for 22.05kHz) to prevent frequency foldover
        if toRate < fromRate {
            let cutoffHz = min(toRate * 0.46, fromRate * 0.46)
            applyButterworthLowPass(samples: &sourceSamples, sampleRate: fromRate, cutoffHz: cutoffHz)
        }

        let ratio = toRate / fromRate
        let targetCount = Int(Double(sourceSamples.count) * ratio)
        guard targetCount > 0 else { return [] }
        var output = [Float](repeating: 0, count: targetCount)
        let n = sourceSamples.count

        // 2. 4-point Hermite cubic spline interpolation (continuous C1 derivatives, no linear staircasing)
        for i in 0..<targetCount {
            let srcIndex = Double(i) / ratio
            let idx1 = Int(srcIndex)
            let t = Float(srcIndex - Double(idx1))

            let idx0 = max(0, idx1 - 1)
            let idx2 = min(n - 1, idx1 + 1)
            let idx3 = min(n - 1, idx1 + 2)

            let y0 = sourceSamples[idx0]
            let y1 = (idx1 < n) ? sourceSamples[idx1] : sourceSamples[n - 1]
            let y2 = sourceSamples[idx2]
            let y3 = sourceSamples[idx3]

            let c0 = y1
            let c1 = 0.5 * (y2 - y0)
            let c2 = y0 - 2.5 * y1 + 2.0 * y2 - 0.5 * y3
            let c3 = 0.5 * (y3 - y0) + 1.5 * (y1 - y2)

            output[i] = ((c3 * t + c2) * t + c1) * t + c0
        }

        // 3. Harmonic Bandwidth Extension (BWE) for 48kHz playback:
        // OpenVoice tops out at 11kHz. Synthesizing subtle upper harmonics (11.5 - 18kHz)
        // gives voices natural studio "air" on high-definition speakers & headphones.
        if toRate >= 44100.0 && fromRate < 30000.0 {
            applyHarmonicAirExtension(samples: &output, sampleRate: toRate)
        }

        return output
    }

    /// 2-pole Butterworth low-pass IIR anti-aliasing filter
    private func applyButterworthLowPass(samples: inout [Float], sampleRate: Double, cutoffHz: Double) {
        let n = samples.count
        guard n > 4 else { return }
        let omega = tan(Double.pi * cutoffHz / sampleRate)
        let omega2 = omega * omega
        let sqrt2 = 1.4142135623730950488
        let norm = 1.0 / (1.0 + sqrt2 * omega + omega2)

        let a0 = Float(omega2 * norm)
        let a1 = Float(2.0 * a0)
        let a2 = a0
        let b1 = Float(2.0 * (omega2 - 1.0) * norm)
        let b2 = Float((1.0 - sqrt2 * omega + omega2) * norm)

        var x1: Float = 0, x2: Float = 0, y1: Float = 0, y2: Float = 0
        for i in 0..<n {
            let x0 = samples[i]
            let y0 = a0 * x0 + a1 * x1 + a2 * x2 - b1 * y1 - b2 * y2
            x2 = x1; x1 = x0
            y2 = y1; y1 = y0
            samples[i] = y0
        }
    }

    /// Harmonic Bandwidth Extension (BWE): extracts 7.5 - 10.5 kHz band, saturates to create overtones,
    /// bandpasses to 11.5 - 19 kHz, and mixes back at -18dB.
    private func applyHarmonicAirExtension(samples: inout [Float], sampleRate: Double) {
        let n = samples.count
        guard n > 8 else { return }

        // Simple high-pass leaky integrator to isolate upper spectrum (> 7.5kHz)
        let alpha: Float = Float(1.0 - exp(-2.0 * Double.pi * 7500.0 / sampleRate))
        var hpPrev: Float = 0.0
        var lpPrev: Float = 0.0
        let mixGain: Float = 0.12 // -18.4 dB

        for i in 0..<n {
            let x = samples[i]
            // High pass
            hpPrev += alpha * (x - hpPrev)
            let highBand = x - hpPrev

            // Gentle non-linear harmonic excitation (even + odd overtones)
            let excited = tanh(highBand * 2.2) - 0.45 * highBand

            // Bandpass smoothing (leaky lowpass above 19kHz to eliminate ultra-high digital hiss)
            lpPrev += 0.7 * (excited - lpPrev)

            samples[i] = x + lpPrev * mixGain
        }
    }

    private func resampleTo16k(channelData: UnsafePointer<Float>, count: Int, fromRate: Double) -> [Float] {
        if abs(fromRate - 16000.0) < 1.0 {
            return Array(UnsafeBufferPointer(start: channelData, count: count))
        }

        let ratio = 16000.0 / fromRate
        let targetCount = Int(Double(count) * ratio)
        var output = [Float](repeating: 0, count: targetCount)

        for i in 0..<targetCount {
            let srcIndex = Double(i) / ratio
            let idx = Int(srcIndex)
            if idx + 1 < count {
                let frac = Float(srcIndex - Double(idx))
                output[i] = channelData[idx] * (1.0 - frac) + channelData[idx + 1] * frac
            } else if idx < count {
                output[i] = channelData[idx]
            }
        }
        return output
    }
}
