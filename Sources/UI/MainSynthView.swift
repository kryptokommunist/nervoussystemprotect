import SwiftUI

final class SynthViewState: ObservableObject {
    @Published var selectedTab: Int = CommandLine.arguments.contains("--tab-rvc") ? 1 : 0
}

public struct MainSynthView: View {
    @StateObject private var deviceManager = AudioDeviceManager()
    @StateObject private var audioEngine = AppAudioEngine()
    @StateObject private var rvcController = AudioController()
    @StateObject private var viewState = SynthViewState()

    public init() {}

    private var isTestingMode: Bool {
        CommandLine.arguments.contains(where: { $0.starts(with: "--test") || $0.starts(with: "--check") || $0.starts(with: "--verify") })
    }

    public var body: some View {
        ZStack {
            // Elegant obsidian studio backdrop
            SynthTheme.panelBackground
                .ignoresSafeArea()

            VStack(spacing: 14) {
                // TOP HEADER & NAVIGATION BAR
                HStack(alignment: .center, spacing: 14) {
                    AppLogoView(size: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("Nervous System Protect")
                                .font(.system(size: 17, weight: .bold, design: .default))
                                .foregroundColor(SynthTheme.textBright)

                            Text("MODEL NSP-1")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(SynthTheme.ledAmber.opacity(0.15))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                .stroke(SynthTheme.ledAmber.opacity(0.5), lineWidth: 0.8)
                                        )
                                )
                                .foregroundColor(SynthTheme.ledAmber)
                        }

                        Text("Real-Time Sensory Soother & Neural Voice Transformer")
                            .font(.system(size: 9.5, weight: .medium, design: .default))
                            .foregroundColor(SynthTheme.textDim)
                    }

                    Spacer()

                    // DELIGHTFUL MODE SWITCHER (SEGMENTED PILL)
                    HStack(spacing: 4) {
                        ModeTabButton(
                            title: "Sensory Soother",
                            icon: "waveform.path.ecg",
                            isSelected: viewState.selectedTab == 0
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if viewState.selectedTab != 0 {
                                    viewState.selectedTab = 0
                                    if rvcController.isRunning {
                                        rvcController.stop()
                                    }
                                    if !audioEngine.isRunning {
                                        audioEngine.start()
                                    }
                                }
                            }
                        }

                        ModeTabButton(
                            title: "Neural Voice (MLX)",
                            icon: "brain.head.profile",
                            isSelected: viewState.selectedTab == 1
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if viewState.selectedTab != 1 {
                                    viewState.selectedTab = 1
                                    if audioEngine.isRunning {
                                        audioEngine.stop()
                                    }
                                    if !rvcController.isRunning {
                                        rvcController.start()
                                    }
                                }
                            }
                        }
                    }
                    .padding(3)
                    .background(Color.black.opacity(0.45))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))

                    // Engine Status Pill
                    let isCurrentRunning = (viewState.selectedTab == 0) ? audioEngine.isRunning : rvcController.isRunning
                    HStack(spacing: 5) {
                        Circle()
                            .fill(isCurrentRunning ? SynthTheme.ledGreen : Color.red.opacity(0.8))
                            .frame(width: 7, height: 7)
                            .shadow(color: isCurrentRunning ? SynthTheme.ledGreen.opacity(0.8) : Color.clear, radius: 3)

                        Text(isCurrentRunning ? "ACTIVE" : "STANDBY")
                            .font(.system(size: 9, weight: .bold, design: .default))
                            .foregroundColor(isCurrentRunning ? SynthTheme.ledGreen : SynthTheme.textDim)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.06), lineWidth: 1))
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)

                // Error Notification Banner if any
                if let error = audioEngine.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(SynthTheme.ledAmber)
                        Text(error)
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundColor(SynthTheme.textBright)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.red.opacity(0.2))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.4), lineWidth: 1))
                    .padding(.horizontal, 18)
                }

                // Global Device Routing Bar (ACTIVE ON BOTH TABS)
                DeviceSelectorView(
                    deviceManager: deviceManager,
                    audioEngine: audioEngine,
                    rvcController: rvcController,
                    selectedTab: viewState.selectedTab
                )
                .padding(.horizontal, 18)

                // MAIN CONTENT AREA
                if viewState.selectedTab == 0 {
                    VStack(spacing: 12) {
                        // TIER 1: EMOTIONAL TONE NEUTRALIZER (AFFECT DE-ESCALATOR)
                        AffectNeutralizerPanel(audioEngine: audioEngine)

                        // TIER 2: STUDIO VOICE SHAPING MODULES
                        HStack(alignment: .top, spacing: 12) {
                            // MODULE 1: PITCH ENGINE
                            SynthModuleCard(title: "HARMONIC PITCH", icon: "tuningfork") {
                                VStack(spacing: 12) {
                                    HStack(spacing: 16) {
                                        KnobView(
                                            title: "Semitones",
                                            value: $audioEngine.pitchSemitones,
                                            range: -12.0...12.0,
                                            defaultValue: 0.0,
                                            unit: "st",
                                            format: "%+.1f",
                                            isBipolar: true,
                                            accentColor: SynthTheme.ledCyan,
                                            size: 60
                                        )

                                        KnobView(
                                            title: "Fine Cents",
                                            value: $audioEngine.pitchCents,
                                            range: -100.0...100.0,
                                            defaultValue: 0.0,
                                            unit: "¢",
                                            format: "%+.0f",
                                            isBipolar: true,
                                            accentColor: SynthTheme.ledCyan,
                                            size: 48
                                        )
                                    }

                                    // Quick Pitch Presets for Nervous System Protection
                                    VStack(spacing: 4) {
                                        Text("SOOTHING PRESETS")
                                            .font(.system(size: 8, weight: .bold, design: .default))
                                            .foregroundColor(SynthTheme.textDim)

                                        HStack(spacing: 5) {
                                            PresetButton(label: "-1 st", active: audioEngine.pitchSemitones == -1.0) {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    audioEngine.pitchSemitones = -1.0
                                                    audioEngine.pitchCents = 0.0
                                                }
                                            }
                                            PresetButton(label: "-2 st", active: audioEngine.pitchSemitones == -2.0) {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    audioEngine.pitchSemitones = -2.0
                                                    audioEngine.pitchCents = 0.0
                                                }
                                            }
                                            PresetButton(label: "432 Hz", active: audioEngine.pitchCents == -32.0 && audioEngine.pitchSemitones == 0.0) {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    audioEngine.pitchSemitones = 0.0
                                                    audioEngine.pitchCents = -32.0
                                                }
                                            }
                                            PresetButton(label: "Reset", active: audioEngine.pitchSemitones == 0.0 && audioEngine.pitchCents == 0.0) {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    audioEngine.pitchSemitones = 0.0
                                                    audioEngine.pitchCents = 0.0
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // MODULE 2: ACOUSTIC CALMING FILTER
                            SynthModuleCard(title: "WARMTH FILTER", icon: "waveform.badge.minus") {
                                VStack(spacing: 12) {
                                    KnobView(
                                        title: "High Cutoff",
                                        value: $audioEngine.cutoffFrequency,
                                        range: 1000.0...20000.0,
                                        defaultValue: 20000.0,
                                        unit: audioEngine.cutoffFrequency >= 19900 ? "FLAT" : "Hz",
                                        format: audioEngine.cutoffFrequency >= 10000 ? "%.0f" : "%.0f",
                                        isBipolar: false,
                                        accentColor: SynthTheme.ledAmber,
                                        size: 60
                                    )

                                    Text(audioEngine.cutoffFrequency >= 19900 ? "Full Transparency" : "Tames harsh highs & audio fatigue")
                                        .font(.system(size: 8.5, weight: .medium, design: .default))
                                        .foregroundColor(SynthTheme.textDim)
                                        .multilineTextAlignment(.center)
                                        .frame(height: 24)
                                }
                            }

                            // MODULE 3: MIX & DYNAMICS
                            SynthModuleCard(title: "MIX & OUTPUT", icon: "slider.horizontal.3") {
                                HStack(spacing: 14) {
                                    KnobView(
                                        title: "Mix",
                                        value: $audioEngine.dryWetMix,
                                        range: 0.0...1.0,
                                        defaultValue: 1.0,
                                        unit: "%",
                                        format: "%.0f",
                                        displayMultiplier: 100.0,
                                        isBipolar: false,
                                        accentColor: SynthTheme.ledAmber,
                                        size: 52
                                    )

                                    KnobView(
                                        title: "Gain",
                                        value: $audioEngine.masterVolume,
                                        range: 0.0...1.5,
                                        defaultValue: 1.0,
                                        unit: "x",
                                        format: "%.2f",
                                        isBipolar: false,
                                        accentColor: SynthTheme.ledGreen,
                                        size: 52
                                    )
                                }
                            }

                            // MODULE 4: MONITORING
                            SynthModuleCard(title: "MONITOR", icon: "chart.bar.fill") {
                                VUMeterView(
                                    leftLevel: audioEngine.leftLevel,
                                    rightLevel: audioEngine.rightLevel
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                } else {
                    VoiceChangerView(controller: rvcController)
                        .padding(.horizontal, 18)
                }

                Spacer(minLength: 4)

                // BOTTOM STATUS & HELPER FOOTER
                HStack(alignment: .center) {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 10))
                            .foregroundColor(SynthTheme.ledAmber)

                        Text("Tip: Set macOS Output to 'BlackHole 2ch' in System Settings to automatically route and soothe all audio.")
                            .font(.system(size: 9.5, weight: .regular, design: .default))
                            .foregroundColor(SynthTheme.textDim)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 16)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(SynthTheme.ledCyan)
                            .frame(width: 4, height: 4)
                        Text("LATENCY: < 1.5ms (CoreAudio SIMD)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(SynthTheme.ledCyan)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(SynthTheme.ledCyan.opacity(0.1))
                    .cornerRadius(4)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .frame(minWidth: 920, idealWidth: 960, minHeight: 700, idealHeight: 720)
        .onAppear {
            guard !isTestingMode else { return }
            initializeDefaults()
        }
        .onReceive(deviceManager.$inputDevices) { _ in
            guard !isTestingMode else { return }
            if audioEngine.selectedInputDevice == nil {
                if let dev = deviceManager.preferredInputDevice() {
                    audioEngine.selectedInputDevice = dev
                }
            }
            if rvcController.selectedInputDevice == nil {
                let mic = deviceManager.preferredMicrophone() ?? deviceManager.getDefaultDevice(isInput: true)
                if let mic = mic {
                    rvcController.selectedInputDevice = mic
                }
            }
            if viewState.selectedTab == 0 {
                if !audioEngine.isRunning && !audioEngine.userStopped && audioEngine.selectedInputDevice != nil && audioEngine.selectedOutputDevice != nil {
                    audioEngine.start()
                }
            } else {
                if !rvcController.isRunning && !rvcController.userStopped && rvcController.selectedInputDevice != nil && rvcController.selectedOutputDevice != nil {
                    rvcController.start()
                }
            }
        }
        .onReceive(deviceManager.$outputDevices) { _ in
            guard !isTestingMode else { return }
            if audioEngine.selectedOutputDevice == nil {
                if let defaultOut = deviceManager.preferredOutputDevice() {
                    audioEngine.selectedOutputDevice = defaultOut
                }
            }
            if rvcController.selectedOutputDevice == nil {
                if let defaultOut = deviceManager.preferredOutputDevice() {
                    rvcController.selectedOutputDevice = defaultOut
                }
            }
            if viewState.selectedTab == 0 {
                if !audioEngine.isRunning && !audioEngine.userStopped && audioEngine.selectedInputDevice != nil && audioEngine.selectedOutputDevice != nil {
                    audioEngine.start()
                }
            } else {
                if !rvcController.isRunning && !rvcController.userStopped && rvcController.selectedInputDevice != nil && rvcController.selectedOutputDevice != nil {
                    rvcController.start()
                }
            }
        }
    }

    private func initializeDefaults() {
        guard !isTestingMode else { return }
        if let dev = deviceManager.preferredInputDevice() {
            audioEngine.selectedInputDevice = dev
        }

        let mic = deviceManager.preferredMicrophone() ?? deviceManager.getDefaultDevice(isInput: true)
        if let mic = mic {
            rvcController.selectedInputDevice = mic
        }

        if let defaultOut = deviceManager.preferredOutputDevice() {
            audioEngine.selectedOutputDevice = defaultOut
            rvcController.selectedOutputDevice = defaultOut
        }

        if viewState.selectedTab == 0 {
            if !audioEngine.isRunning && !audioEngine.userStopped && audioEngine.selectedInputDevice != nil && audioEngine.selectedOutputDevice != nil {
                audioEngine.start()
            }
        } else {
            if !rvcController.isRunning && !rvcController.userStopped && rvcController.selectedInputDevice != nil && rvcController.selectedOutputDevice != nil {
                rvcController.start()
            }
        }
    }
}

// Module Container Card
private struct SynthModuleCard<Content: View>: View {
    let title: String
    var icon: String? = nil
    let content: () -> Content

    init(title: String, icon: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 8.5))
                        .foregroundColor(SynthTheme.ledCyan)
                }
                Text(title)
                    .font(.system(size: 8.5, weight: .bold, design: .default))
                    .foregroundColor(SynthTheme.sectionHeader)
                    .tracking(0.6)
            }
            .padding(.top, 4)

            Divider()
                .background(Color.white.opacity(0.08))

            content()
                .padding(.vertical, 4)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [SynthTheme.panelPlate, Color(red: 0.08, green: 0.09, blue: 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

// Quick Preset Button
private struct PresetButton: View {
    let label: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 8.5, weight: active ? .bold : .medium, design: .default))
                .foregroundColor(active ? Color.black : SynthTheme.textDim)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(active ? SynthTheme.ledCyan : Color.black.opacity(0.4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(active ? SynthTheme.ledCyan : Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

// Mode Selection Tab Button
private struct ModeTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .default))
            }
            .foregroundColor(isSelected ? Color.white : SynthTheme.textDim)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? SynthTheme.panelPlateElevated : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isSelected ? SynthTheme.ledCyan.opacity(0.6) : Color.clear, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// Affect De-escalator & Emotion Neutralizer Rack
private struct AffectNeutralizerPanel: View {
    @ObservedObject var audioEngine: AppAudioEngine

    var body: some View {
        VStack(spacing: 8) {
            // Header Bar with Presets
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundColor(SynthTheme.ledCyan)

                    Text("AFFECT DE-ESCALATOR")
                        .font(.system(size: 9.5, weight: .bold, design: .default))
                        .foregroundColor(SynthTheme.sectionHeader)
                        .tracking(0.6)
                }

                Text("• Tone & Harshness Soother")
                    .font(.system(size: 8.5, weight: .medium, design: .default))
                    .foregroundColor(SynthTheme.textDim)

                Spacer()

                // Quick Presets
                HStack(spacing: 5) {
                    ForEach(AffectPreset.allCases) { preset in
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                audioEngine.applyAffectPreset(preset)
                            }
                        }) {
                            HStack(spacing: 4) {
                                presetIcon(for: preset)
                                Text(presetLabel(for: preset))
                                    .font(.system(size: 8.5, weight: audioEngine.selectedAffectPreset == preset ? .bold : .medium, design: .default))
                            }
                            .foregroundColor(audioEngine.selectedAffectPreset == preset ? Color.black : SynthTheme.textDim)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(audioEngine.selectedAffectPreset == preset ? SynthTheme.ledCyan : Color.black.opacity(0.4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .stroke(audioEngine.selectedAffectPreset == preset ? SynthTheme.ledCyan : Color.white.opacity(0.08), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.top, 2)

            Divider()
                .background(Color.white.opacity(0.08))

            HStack(alignment: .center, spacing: 14) {
                // 1. Live Scope Display (Left)
                AffectScopeView(audioEngine: audioEngine)
                    .frame(maxWidth: .infinity)

                // 2. Master Affect Damping Macro Knob (Center Hero Dial)
                VStack(spacing: 6) {
                    KnobView(
                        title: "Calm",
                        value: $audioEngine.masterDamping,
                        range: 0.0...1.0,
                        defaultValue: 0.0,
                        unit: "%",
                        format: "%.0f",
                        displayMultiplier: 100.0,
                        isBipolar: false,
                        accentColor: SynthTheme.ledCyan,
                        size: 56
                    )

                    Text("MASTER CALM")
                        .font(.system(size: 7.5, weight: .bold, design: .default))
                        .foregroundColor(SynthTheme.textDim)
                }
                .padding(.horizontal, 4)

                Divider()
                    .background(Color.white.opacity(0.08))
                    .frame(height: 95)

                // 3. Fine-Tuning Controls (Right)
                HStack(spacing: 12) {
                    // Column 1: Inflection Shaping
                    VStack(spacing: 8) {
                        KnobView(
                            title: "Prosody",
                            value: $audioEngine.prosodyFlatten,
                            range: 0.0...1.0,
                            defaultValue: 0.0,
                            unit: "%",
                            format: "%.0f",
                            displayMultiplier: 100.0,
                            accentColor: SynthTheme.ledCyan,
                            size: 38
                        )

                        KnobView(
                            title: "Plosive",
                            value: $audioEngine.attackSoftener,
                            range: 0.0...1.0,
                            defaultValue: 0.0,
                            unit: "%",
                            format: "%.0f",
                            displayMultiplier: 100.0,
                            accentColor: SynthTheme.ledCyan,
                            size: 38
                        )
                    }

                    // Column 2: Dynamics & Breath
                    VStack(spacing: 8) {
                        KnobView(
                            title: "Leveler",
                            value: $audioEngine.syllableLeveler,
                            range: 0.0...1.0,
                            defaultValue: 0.0,
                            unit: "%",
                            format: "%.0f",
                            displayMultiplier: 100.0,
                            accentColor: SynthTheme.ledAmber,
                            size: 38
                        )

                        KnobView(
                            title: "Sigh Gate",
                            value: $audioEngine.breathGate,
                            range: 0.0...1.0,
                            defaultValue: 0.0,
                            unit: "%",
                            format: "%.0f",
                            displayMultiplier: 100.0,
                            accentColor: SynthTheme.ledAmber,
                            size: 38
                        )
                    }

                    // Column 3: Harshness & Detach
                    VStack(spacing: 8) {
                        KnobView(
                            title: "3.4k Notch",
                            value: $audioEngine.urgencyNotchDb,
                            range: -18.0...0.0,
                            defaultValue: 0.0,
                            unit: "dB",
                            format: "%.0f",
                            accentColor: SynthTheme.ledGreen,
                            size: 38
                        )

                        KnobView(
                            title: "Detach",
                            value: $audioEngine.robotInharmonicity,
                            range: 0.0...1.0,
                            defaultValue: 0.0,
                            unit: "%",
                            format: "%.0f",
                            displayMultiplier: 100.0,
                            accentColor: SynthTheme.ledCyan,
                            size: 38
                        )
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [SynthTheme.panelPlate, Color(red: 0.08, green: 0.09, blue: 0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func presetLabel(for preset: AffectPreset) -> String {
        switch preset {
        case .natural: return "Natural"
        case .calmSoothe: return "Calm Soothe"
        case .deadpan: return "Deadpan"
        case .robotDrone: return "Zen Drone"
        }
    }

    @ViewBuilder
    private func presetIcon(for preset: AffectPreset) -> some View {
        switch preset {
        case .natural:
            Image(systemName: "leaf.fill").font(.system(size: 8))
        case .calmSoothe:
            Image(systemName: "heart.fill").font(.system(size: 8))
        case .deadpan:
            Image(systemName: "minus").font(.system(size: 8, weight: .bold))
        case .robotDrone:
            Image(systemName: "waveform").font(.system(size: 8))
        }
    }
}
