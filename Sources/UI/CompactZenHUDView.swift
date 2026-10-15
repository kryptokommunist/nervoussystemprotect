import SwiftUI

/// Compact Zen HUD View (Concept 4)
/// A minimalist, distraction-free floating desktop companion for nervoussystemprotect.
/// Features dual-mode support:
///   1. Sensory Soother (Affect De-escalator & Master Calm knob with embedded 3D Neural Net)
///   2. Neural Voice (Apple Silicon MLX & OpenVoice with real-time timbre knob & voice presets)
/// Complete with interactive audio source/destination menus and neural model selector.
public struct CompactZenHUDView: View {
    @ObservedObject var audioEngine: AppAudioEngine
    @ObservedObject var rvcController: AudioController
    @ObservedObject var deviceManager: AudioDeviceManager
    @Binding var selectedTab: Int
    @Binding var isExpandedToStudio: Bool

    public init(
        audioEngine: AppAudioEngine,
        rvcController: AudioController,
        deviceManager: AudioDeviceManager,
        selectedTab: Binding<Int>,
        isExpandedToStudio: Binding<Bool>
    ) {
        self.audioEngine = audioEngine
        self.rvcController = rvcController
        self.deviceManager = deviceManager
        self._selectedTab = selectedTab
        self._isExpandedToStudio = isExpandedToStudio
    }

    // Binding for neural pitch normalized to 0.0 ... 1.0 (mapping -12 st ... +12 st)
    private var pitchProgressBinding: Binding<Float> {
        Binding(
            get: {
                let clamped = max(-12.0, min(12.0, Double(rvcController.pitchShiftSemitones)))
                return Float((clamped + 12.0) / 24.0)
            },
            set: { progress in
                let semitones = round((Double(progress) * 24.0) - 12.0)
                rvcController.pitchShiftSemitones = Float(semitones)
            }
        )
    }

    private func selectInputDevice(_ dev: AudioDeviceInfo) {
        if selectedTab == 0 {
            audioEngine.setInputDevice(dev)
            rvcController.setInputDevice(dev, autoStartIfReady: false)
            if rvcController.isRunning {
                rvcController.stop()
            }
        } else {
            rvcController.setInputDevice(dev)
            audioEngine.setInputDevice(dev, autoStartIfReady: false)
            if audioEngine.isRunning {
                audioEngine.stop()
            }
        }
    }

    private func selectOutputDevice(_ dev: AudioDeviceInfo) {
        if selectedTab == 0 {
            audioEngine.setOutputDevice(dev)
            rvcController.setOutputDevice(dev, autoStartIfReady: false)
            if rvcController.isRunning {
                rvcController.stop()
            }
        } else {
            rvcController.setOutputDevice(dev)
            audioEngine.setOutputDevice(dev, autoStartIfReady: false)
            if audioEngine.isRunning {
                audioEngine.stop()
            }
        }
    }

    public var body: some View {
        ZStack {
            // Dark obsidian floating island backdrop with gentle vignette
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.09, blue: 0.12),
                    Color(red: 0.04, green: 0.05, blue: 0.07)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                // 1. TOP HEADER & STUDIO EXPAND
                HStack(alignment: .center, spacing: 10) {
                    AppLogoView(size: 24)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Nervous System Protect")
                            .font(.system(size: 12.5, weight: .bold, design: .default))
                            .foregroundColor(SynthTheme.textBright)

                        Text("MODEL NSP-1 • ZEN COMPANION")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(SynthTheme.ledCyan)
                    }

                    Spacer()

                    // Compact Segmented Mode Selector [ Soother | Neural Voice ]
                    HStack(spacing: 2) {
                        modeTabButton(title: "Soother", icon: "waveform.path.badge.minus", tabIndex: 0)
                        modeTabButton(title: "Neural Voice", icon: "brain.head.profile", tabIndex: 1)
                    }
                    .padding(2)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 0.8))

                    // Expand to Full Studio Button
                    Button(action: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            isExpandedToStudio = true
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 8, weight: .bold))
                            Text("Studio View")
                                .font(.system(size: 8.5, weight: .bold, design: .default))
                        }
                        .foregroundColor(SynthTheme.ledCyan)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(SynthTheme.ledCyan.opacity(0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(SynthTheme.ledCyan.opacity(0.5), lineWidth: 0.8)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Expand to the comprehensive Studio Mode (Concept 1)")
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)

                // 2. SUB-HEADER: INTERACTIVE SOURCE & DESTINATION PICKERS + ENGINE STATUS
                HStack(spacing: 6) {
                    let currentInput = (selectedTab == 0 ? audioEngine.selectedInputDevice : rvcController.selectedInputDevice) ?? audioEngine.selectedInputDevice ?? rvcController.selectedInputDevice
                    let currentOutput = (selectedTab == 0 ? audioEngine.selectedOutputDevice : rvcController.selectedOutputDevice) ?? audioEngine.selectedOutputDevice ?? rvcController.selectedOutputDevice

                    // INTERACTIVE AUDIO SOURCE PICKER MENU
                    Menu {
                        ForEach(deviceManager.inputDevices) { device in
                            Button(action: { selectInputDevice(device) }) {
                                HStack {
                                    Text(device.name)
                                    if currentInput?.id == device.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 7.5))
                                .foregroundColor(SynthTheme.ledCyan)
                            Text(currentInput?.name ?? "Select Input...")
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 125, alignment: .leading)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 6.5, weight: .bold))
                                .foregroundColor(SynthTheme.textDim)
                        }
                        .font(.system(size: 8, weight: .medium, design: .default))
                        .foregroundColor(SynthTheme.textBright)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.08), lineWidth: 0.8))
                    }
                    .menuStyle(.borderlessButton)
                    .help("Select Audio Input Source")

                    Image(systemName: "arrow.right")
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundColor(SynthTheme.textDim)

                    // INTERACTIVE AUDIO DESTINATION PICKER MENU
                    Menu {
                        ForEach(deviceManager.outputDevices) { device in
                            Button(action: { selectOutputDevice(device) }) {
                                HStack {
                                    Text(device.name)
                                    if currentOutput?.id == device.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 7.5))
                                .foregroundColor(SynthTheme.ledGreen)
                            Text(currentOutput?.name ?? "Select Output...")
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 125, alignment: .leading)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 6.5, weight: .bold))
                                .foregroundColor(SynthTheme.textDim)
                        }
                        .font(.system(size: 8, weight: .medium, design: .default))
                        .foregroundColor(SynthTheme.textBright)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(5)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.08), lineWidth: 0.8))
                    }
                    .menuStyle(.borderlessButton)
                    .help("Select Audio Destination / Output")

                    Spacer()

                    if selectedTab == 0 {
                        // Soother Active State Toggle
                        statusButton(
                            isActive: audioEngine.isRunning,
                            activeLabel: "ACTIVE",
                            inactiveLabel: "STANDBY"
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                if audioEngine.isRunning {
                                    audioEngine.userStopped = true
                                    audioEngine.stop()
                                } else {
                                    audioEngine.userStopped = false
                                    if rvcController.isRunning {
                                        rvcController.userStopped = true
                                        rvcController.stop()
                                    }
                                    audioEngine.start()
                                }
                            }
                        }
                    } else {
                        // Neural Voice Active State Toggle
                        statusButton(
                            isActive: rvcController.isRunning,
                            activeLabel: "ACTIVE",
                            inactiveLabel: "STANDBY"
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                if rvcController.isRunning {
                                    rvcController.userStopped = true
                                    rvcController.stop()
                                } else {
                                    rvcController.userStopped = false
                                    if audioEngine.isRunning {
                                        audioEngine.userStopped = true
                                        audioEngine.stop()
                                    }
                                    rvcController.start()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)

                Spacer(minLength: 0)

                // 3. MAIN CENTER HUD
                if selectedTab == 0 {
                    // TAB 0: SENSORY SOOTHER VIEW
                    sootherHUDView
                } else {
                    // TAB 1: NEURAL VOICE TRANSFORMER VIEW
                    neuralHUDView
                }

                Spacer(minLength: 0)

                // 4. BOTTOM PRESET & CONTROL BAR
                if selectedTab == 0 {
                    sootherPresetBar
                } else {
                    neuralPresetBar
                }
            }
        }
        .frame(minWidth: 540, idealWidth: 560, maxWidth: 580, minHeight: 380, idealHeight: 400, maxHeight: 420)
    }

    // MARK: - Sensory Soother Components (Tab 0)

    private var sootherHUDView: some View {
        HStack(alignment: .center, spacing: 18) {
            // Voice Stress Input Meter
            VStack(spacing: 3) {
                Text("VOICE STRESS")
                    .font(.system(size: 7.5, weight: .bold, design: .default))
                    .foregroundColor(SynthTheme.textDim)

                Text("INPUT")
                    .font(.system(size: 7, weight: .medium, design: .default))
                    .foregroundColor(SynthTheme.textMuted)

                VerticalCompactMeter(
                    level: audioEngine.leftLevel,
                    color: SynthTheme.ledAmber
                )
                .frame(height: 105)

                HStack(spacing: 3) {
                    Circle().fill(SynthTheme.ledGreen).frame(width: 3.5, height: 3.5)
                    Text("0.8 ms")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(SynthTheme.ledGreen)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(SynthTheme.ledGreen.opacity(0.12))
                .cornerRadius(3)
            }
            .frame(width: 65)

            // Master Calm Halo Knob
            VStack(spacing: 4) {
                MasterCalmHaloKnob(
                    value: $audioEngine.masterDamping,
                    isVoiceActive: audioEngine.leftLevel > 0.05,
                    activityRMS: audioEngine.leftLevel,
                    title: "MASTER CALM",
                    accentColor: SynthTheme.ledCyan,
                    size: 155
                )

                Text(audioEngine.isBypassed ? "DSP Bypassed" : (audioEngine.masterDamping > 0.05 ? "Soothing Damping Engaged" : "Natural Transparent Audio"))
                    .font(.system(size: 8, weight: .medium, design: .default))
                    .foregroundColor(audioEngine.isBypassed ? SynthTheme.ledAmber : (audioEngine.masterDamping > 0.05 ? SynthTheme.ledCyan : SynthTheme.textDim))
            }

            // Soothed Output Meter
            VStack(spacing: 3) {
                Text("SOOTHED")
                    .font(.system(size: 7.5, weight: .bold, design: .default))
                    .foregroundColor(SynthTheme.textDim)

                Text("OUTPUT")
                    .font(.system(size: 7, weight: .medium, design: .default))
                    .foregroundColor(SynthTheme.textMuted)

                VerticalCompactMeter(
                    level: audioEngine.rightLevel,
                    color: SynthTheme.ledCyan
                )
                .frame(height: 105)

                HStack(spacing: 3) {
                    Circle().fill(SynthTheme.ledCyan).frame(width: 3.5, height: 3.5)
                    Text("MLX Core")
                        .font(.system(size: 7, weight: .bold, design: .default))
                        .foregroundColor(SynthTheme.ledCyan)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(SynthTheme.ledCyan.opacity(0.12))
                .cornerRadius(3)
            }
            .frame(width: 65)
        }
        .padding(.horizontal, 10)
    }

    private var sootherPresetBar: some View {
        HStack(spacing: 7) {
            ForEach(AffectPreset.allCases) { preset in
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        audioEngine.applyAffectPreset(preset)
                    }
                }) {
                    Text(presetCompactLabel(preset))
                        .font(.system(size: 8.5, weight: audioEngine.selectedAffectPreset == preset ? .bold : .medium, design: .default))
                        .foregroundColor(audioEngine.selectedAffectPreset == preset ? Color.black : SynthTheme.textBright)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(audioEngine.selectedAffectPreset == preset ? SynthTheme.ledCyan : Color.black.opacity(0.4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(audioEngine.selectedAffectPreset == preset ? SynthTheme.ledCyan : Color.white.opacity(0.08), lineWidth: 0.8)
                                )
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    audioEngine.isBypassed.toggle()
                }
            }) {
                HStack(spacing: 3) {
                    Circle()
                        .fill(audioEngine.isBypassed ? SynthTheme.ledAmber : Color.white.opacity(0.25))
                        .frame(width: 4.5, height: 4.5)
                    Text(audioEngine.isBypassed ? "BYPASS ON" : "BYPASS")
                        .font(.system(size: 8, weight: .semibold, design: .default))
                        .foregroundColor(audioEngine.isBypassed ? SynthTheme.ledAmber : SynthTheme.textDim)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(audioEngine.isBypassed ? SynthTheme.ledAmber.opacity(0.18) : Color.black.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(audioEngine.isBypassed ? SynthTheme.ledAmber.opacity(0.6) : Color.white.opacity(0.06), lineWidth: 0.8)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Neural Voice Components (Tab 1)

    private var neuralHUDView: some View {
        HStack(alignment: .center, spacing: 18) {
            // Left Column: Mic Input Meter
            VStack(spacing: 3) {
                Text("MIC INPUT")
                    .font(.system(size: 7.5, weight: .bold, design: .default))
                    .foregroundColor(SynthTheme.textDim)

                Text("LEVEL")
                    .font(.system(size: 7, weight: .medium, design: .default))
                    .foregroundColor(SynthTheme.textMuted)

                VerticalCompactMeter(
                    level: rvcController.inputLevel,
                    color: SynthTheme.ledGreen
                )
                .frame(height: 105)

                HStack(spacing: 3) {
                    Circle().fill(rvcController.isVoiceActive ? SynthTheme.ledGreen : Color.white.opacity(0.3)).frame(width: 3.5, height: 3.5)
                    Text(rvcController.isVoiceActive ? "OPEN" : "GATED")
                        .font(.system(size: 7, weight: .bold, design: .default))
                        .foregroundColor(rvcController.isVoiceActive ? SynthTheme.ledGreen : SynthTheme.textDim)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.white.opacity(0.05))
                .cornerRadius(3)
            }
            .frame(width: 65)

            // Center Column: 3D Neural Pitch & Timbre Knob + Interactive Character Selector
            VStack(spacing: 4) {
                MasterCalmHaloKnob(
                    value: pitchProgressBinding,
                    isVoiceActive: rvcController.isVoiceActive,
                    activityRMS: rvcController.inputLevel,
                    title: "PITCH SHIFT",
                    displayValue: String(format: "%+.0f st", rvcController.pitchShiftSemitones),
                    accentColor: SynthTheme.ledPurple,
                    size: 145
                )

                // INTERACTIVE NEURAL MODEL SELECTOR DROPDOWN
                Menu {
                    ForEach(AudioController.availableCharacters) { char in
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                rvcController.selectedCharacter = char
                                rvcController.pitchShiftSemitones = Float(char.defaultPitch)
                            }
                        }) {
                            HStack {
                                Text(char.name)
                                if rvcController.selectedCharacter.id == char.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(SynthTheme.ledPurple)
                        Text(rvcController.selectedCharacter.name)
                            .font(.system(size: 8.5, weight: .bold, design: .default))
                            .foregroundColor(SynthTheme.textBright)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 165)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 6.5, weight: .bold))
                            .foregroundColor(SynthTheme.textDim)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(Color.black.opacity(0.55))
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(SynthTheme.ledPurple.opacity(0.5), lineWidth: 0.8)
                    )
                }
                .menuStyle(.borderlessButton)
                .help("Select Neural Voice Character Model")

                Text(rvcController.isSynthesizingChunk ?
                     "⚡ Synthesizing (\(Int(rvcController.lastInferenceDurationMs))ms)" :
                     "Neural Timbre • \(rvcController.selectedCharacter.name)")
                    .font(.system(size: 7.5, weight: .medium, design: .default))
                    .foregroundColor(rvcController.isSynthesizingChunk ? SynthTheme.ledCyan : SynthTheme.textDim)
                    .lineLimit(1)
            }

            // Right Column: Neural Synthesized Output Meter
            VStack(spacing: 3) {
                Text("NEURAL OUT")
                    .font(.system(size: 7.5, weight: .bold, design: .default))
                    .foregroundColor(SynthTheme.textDim)

                Text(rvcController.selectedCharacter.id.prefix(8).uppercased())
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .foregroundColor(SynthTheme.ledPurple)
                    .lineLimit(1)

                VerticalCompactMeter(
                    level: rvcController.outputLevel,
                    color: SynthTheme.ledPurple
                )
                .frame(height: 105)

                HStack(spacing: 3) {
                    Circle().fill(SynthTheme.ledPurple).frame(width: 3.5, height: 3.5)
                    Text("< 15 ms")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundColor(SynthTheme.ledPurple)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(SynthTheme.ledPurple.opacity(0.12))
                .cornerRadius(3)
            }
            .frame(width: 65)
        }
        .padding(.horizontal, 10)
    }

    private var neuralPresetBar: some View {
        HStack(spacing: 6) {
            // Quick Built-in Character / Preset Pills
            let presets = Array(AudioController.builtinPresets.prefix(4))
            ForEach(presets) { preset in
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        rvcController.applyPreset(preset)
                    }
                }) {
                    HStack(spacing: 3) {
                        Text(preset.emoji)
                            .font(.system(size: 8))
                        Text(preset.name)
                            .font(.system(size: 8, weight: .semibold, design: .default))
                    }
                    .foregroundColor(rvcController.selectedPresetId == preset.id ? Color.black : SynthTheme.textBright)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4.5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(rvcController.selectedPresetId == preset.id ? SynthTheme.ledPurple : Color.black.opacity(0.4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(rvcController.selectedPresetId == preset.id ? SynthTheme.ledPurple : Color.white.opacity(0.08), lineWidth: 0.8)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Test Voice Button
            Button(action: {
                rvcController.testNeuralSynthesis()
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 7.5))
                    Text(rvcController.testSynthesisStatus ?? "Test Voice")
                        .font(.system(size: 8, weight: .bold, design: .default))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(SynthTheme.ledGreen.opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(SynthTheme.ledGreen.opacity(0.6), lineWidth: 0.8)
                        )
                )
                .foregroundColor(SynthTheme.ledGreen)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    // MARK: - Helpers

    private func modeTabButton(title: String, icon: String, tabIndex: Int) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedTab = tabIndex
            }
        }) {
            HStack(spacing: 3.5) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                Text(title)
                    .font(.system(size: 8.5, weight: selectedTab == tabIndex ? .bold : .medium, design: .default))
            }
            .foregroundColor(selectedTab == tabIndex ? Color.white : SynthTheme.textDim)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                selectedTab == tabIndex ?
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(SynthTheme.ledCyan.opacity(0.5), lineWidth: 0.6)) :
                nil
            )
        }
        .buttonStyle(.plain)
    }

    private func statusButton(isActive: Bool, activeLabel: String, inactiveLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3.5) {
                Circle()
                    .fill(isActive ? SynthTheme.ledGreen : Color.red.opacity(0.8))
                    .frame(width: 5, height: 5)
                    .shadow(color: isActive ? SynthTheme.ledGreen.opacity(0.8) : Color.clear, radius: 2)

                Text(isActive ? activeLabel : inactiveLabel)
                    .font(.system(size: 7.5, weight: .bold, design: .default))
                    .foregroundColor(isActive ? Color.white : SynthTheme.textDim)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isActive ? Color(red: 0.08, green: 0.32, blue: 0.15) : Color(white: 0.15))
            )
        }
        .buttonStyle(.plain)
    }

    private func presetCompactLabel(_ preset: AffectPreset) -> String {
        switch preset {
        case .natural: return "Natural"
        case .calmSoothe: return "Calm Soothe"
        case .deadpan: return "Deadpan"
        case .robotDrone: return "Zen Drone"
        }
    }
}

// Compact Vertical Segmented LED Meter
private struct VerticalCompactMeter: View {
    let level: Float
    let color: Color
    let segments: Int = 14

    var body: some View {
        VStack(spacing: 2.5) {
            ForEach((0..<segments).reversed(), id: \.self) { idx in
                let threshold = Float(idx) / Float(segments)
                let isLit = level >= threshold
                let segColor = idx >= 11 ? SynthTheme.ledRed : (idx >= 8 ? SynthTheme.ledAmber : color)

                RoundedRectangle(cornerRadius: 1)
                    .fill(isLit ? segColor : Color.white.opacity(0.06))
                    .frame(width: 12, height: 4)
                    .shadow(color: isLit ? segColor.opacity(0.7) : Color.clear, radius: 2)
            }
        }
        .padding(3.5)
        .background(Color.black.opacity(0.45))
        .cornerRadius(5)
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.06), lineWidth: 0.8))
    }
}
