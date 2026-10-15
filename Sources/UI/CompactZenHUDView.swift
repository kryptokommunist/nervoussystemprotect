import SwiftUI

/// Compact Zen HUD View (Concept 4)
/// A minimalist, distraction-free floating desktop companion for nervoussystemprotect.
/// Features the embedded 3D Neural Net Master Calm Knob, real-time stress vs. soothed metering,
/// quick soothing presets, and a 1-click toggle to expand into the full Studio View (Concept 1).
public struct CompactZenHUDView: View {
    @ObservedObject var audioEngine: AppAudioEngine
    @ObservedObject var rvcController: AudioController
    @ObservedObject var deviceManager: AudioDeviceManager
    @Binding var isExpandedToStudio: Bool

    public init(
        audioEngine: AppAudioEngine,
        rvcController: AudioController,
        deviceManager: AudioDeviceManager,
        isExpandedToStudio: Binding<Bool>
    ) {
        self.audioEngine = audioEngine
        self.rvcController = rvcController
        self.deviceManager = deviceManager
        self._isExpandedToStudio = isExpandedToStudio
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

            VStack(spacing: 12) {
                // 1. TOP HEADER & EXPAND CONTROLS
                HStack(alignment: .center, spacing: 10) {
                    AppLogoView(size: 26)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("nervoussystemprotect")
                            .font(.system(size: 13, weight: .bold, design: .default))
                            .foregroundColor(SynthTheme.textBright)

                        Text("MODEL NSP-1 • ZEN COMPANION")
                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                            .foregroundColor(SynthTheme.ledCyan)
                    }

                    Spacer()

                    // Quick Device Routing Pill
                    let inputName = audioEngine.selectedInputDevice?.name ?? "Mic"
                    let outputName = audioEngine.selectedOutputDevice?.name ?? "Speakers"
                    HStack(spacing: 4) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 8))
                            .foregroundColor(SynthTheme.ledCyan)
                        Text(inputName)
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(SynthTheme.textDim)
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 8))
                            .foregroundColor(SynthTheme.ledGreen)
                        Text(outputName)
                            .lineLimit(1)
                    }
                    .font(.system(size: 8, weight: .medium, design: .default))
                    .foregroundColor(SynthTheme.textDim)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(5)

                    // Power Pill
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            if audioEngine.isRunning {
                                audioEngine.userStopped = true
                                audioEngine.stop()
                            } else {
                                audioEngine.userStopped = false
                                audioEngine.start()
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(audioEngine.isRunning ? SynthTheme.ledGreen : Color.red.opacity(0.8))
                                .frame(width: 6, height: 6)
                                .shadow(color: audioEngine.isRunning ? SynthTheme.ledGreen.opacity(0.8) : Color.clear, radius: 3)

                            Text(audioEngine.isRunning ? "ACTIVE" : "STANDBY")
                                .font(.system(size: 8.5, weight: .bold, design: .default))
                                .foregroundColor(audioEngine.isRunning ? Color.white : SynthTheme.textDim)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(audioEngine.isRunning ? Color(red: 0.08, green: 0.32, blue: 0.15) : Color(white: 0.15))
                        )
                    }
                    .buttonStyle(.plain)

                    // Expand to Full Studio Button
                    Button(action: {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            isExpandedToStudio = true
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("Studio View")
                                .font(.system(size: 9, weight: .bold, design: .default))
                        }
                        .foregroundColor(SynthTheme.ledCyan)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
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
                .padding(.horizontal, 16)
                .padding(.top, 14)

                Spacer(minLength: 2)

                // 2. MAIN CENTER HUD: INPUT STRESS METER | 3D NEURAL MASTER CALM KNOB | SOOTHED OUTPUT METER
                HStack(alignment: .center, spacing: 20) {
                    // LEFT COLUMN: VOICE STRESS (INPUT) METER
                    VStack(spacing: 4) {
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
                        .frame(height: 110)

                        // Latency Badge
                        HStack(spacing: 3) {
                            Circle().fill(SynthTheme.ledGreen).frame(width: 3.5, height: 3.5)
                            Text("0.8 ms")
                                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                .foregroundColor(SynthTheme.ledGreen)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(SynthTheme.ledGreen.opacity(0.12))
                        .cornerRadius(3)
                    }
                    .frame(width: 65)

                    // CENTER HERO: MASTER CALM HALO KNOB WITH 3D NEURAL MESH
                    VStack(spacing: 6) {
                        MasterCalmHaloKnob(
                            value: $audioEngine.masterDamping,
                            isVoiceActive: audioEngine.leftLevel > 0.05,
                            activityRMS: audioEngine.leftLevel,
                            size: 165
                        )

                        Text(audioEngine.isBypassed ? "DSP BYPASSED" : (audioEngine.masterDamping > 0.05 ? "Acoustic De-escalation Active" : "Natural Transparent Audio"))
                            .font(.system(size: 8.5, weight: .medium, design: .default))
                            .foregroundColor(audioEngine.isBypassed ? SynthTheme.ledAmber : (audioEngine.masterDamping > 0.05 ? SynthTheme.ledCyan : SynthTheme.textDim))
                    }

                    // RIGHT COLUMN: SOOTHED (OUTPUT) METER
                    VStack(spacing: 4) {
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
                        .frame(height: 110)

                        // MLX Core Badge
                        HStack(spacing: 3) {
                            Circle().fill(SynthTheme.ledCyan).frame(width: 3.5, height: 3.5)
                            Text("MLX Core")
                                .font(.system(size: 7.5, weight: .bold, design: .default))
                                .foregroundColor(SynthTheme.ledCyan)
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(SynthTheme.ledCyan.opacity(0.12))
                        .cornerRadius(3)
                    }
                    .frame(width: 65)
                }
                .padding(.horizontal, 10)

                Spacer(minLength: 2)

                // 3. BOTTOM QUICK SOOTHING PRESETS BAR
                HStack(spacing: 8) {
                    ForEach(AffectPreset.allCases) { preset in
                        Button(action: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                audioEngine.applyAffectPreset(preset)
                            }
                        }) {
                            Text(presetCompactLabel(preset))
                                .font(.system(size: 8.5, weight: audioEngine.selectedAffectPreset == preset ? .bold : .medium, design: .default))
                                .foregroundColor(audioEngine.selectedAffectPreset == preset ? Color.black : SynthTheme.textBright)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(audioEngine.selectedAffectPreset == preset ? SynthTheme.ledCyan : Color.black.opacity(0.4))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(audioEngine.selectedAffectPreset == preset ? SynthTheme.ledCyan : Color.white.opacity(0.08), lineWidth: 1)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    // Quick Bypass Toggle
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            audioEngine.isBypassed.toggle()
                        }
                    }) {
                        HStack(spacing: 3.5) {
                            Circle()
                                .fill(audioEngine.isBypassed ? SynthTheme.ledAmber : Color.white.opacity(0.25))
                                .frame(width: 5, height: 5)
                            Text(audioEngine.isBypassed ? "BYPASS ON" : "Bypass")
                                .font(.system(size: 8.5, weight: .semibold, design: .default))
                                .foregroundColor(audioEngine.isBypassed ? SynthTheme.ledAmber : SynthTheme.textDim)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4.5)
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
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .frame(minWidth: 520, idealWidth: 540, maxWidth: 560, minHeight: 350, idealHeight: 370, maxHeight: 390)
    }

    private func presetCompactLabel(_ preset: AffectPreset) -> String {
        switch preset {
        case .natural: return "Natural"
        case .calmSoothe: return "Calm Soothe"
        case .deadpan: return "Deadpan Whisper"
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
        .padding(4)
        .background(Color.black.opacity(0.45))
        .cornerRadius(5)
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.06), lineWidth: 0.8))
    }
}
