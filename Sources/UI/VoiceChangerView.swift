import SwiftUI
import AVFoundation

public struct VoiceChangerView: View {
    @ObservedObject var controller: AudioController
    @State private var isShowingSavePresetDialog: Bool = false
    @State private var isShowingModelDetails: Bool = false
    @State private var newPresetName: String = ""
    @State private var newPresetEmoji: String = "⭐"

    public init(controller: AudioController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 12) {
            // Header: Title & Start/Stop Controls
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Neural Voice Transformer")
                            .font(.system(size: 14, weight: .bold, design: .default))
                            .foregroundColor(SynthTheme.textBright)

                        Text("OPENVOICE V2")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(SynthTheme.ledCyan.opacity(0.15))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .stroke(SynthTheme.ledCyan.opacity(0.5), lineWidth: 0.8)
                                    )
                            )
                            .foregroundColor(SynthTheme.ledCyan)
                    }

                    Text("Neural Tone Color Converter • Real-Time Voice Transformation")
                        .font(.system(size: 9, weight: .medium, design: .default))
                        .foregroundColor(SynthTheme.textDim)
                }
            }
            .padding(.top, 2)

            // Start Error Alert Banner (if start failed or threw)
            if let err = controller.errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("VOICE START FAILURE")
                            .font(.system(size: 9.5, weight: .bold, design: .default))
                            .foregroundColor(.white)
                        Text(err)
                            .font(.system(size: 8.5, weight: .medium, design: .default))
                            .foregroundColor(Color.white.opacity(0.85))
                    }

                    Spacer()

                    Button(action: {
                        controller.errorMessage = nil
                        controller.start()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("RETRY")
                        }
                        .font(.system(size: 9, weight: .bold, design: .default))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    Button(action: { controller.errorMessage = nil }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.7))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(red: 0.35, green: 0.08, blue: 0.08))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.red.opacity(0.5), lineWidth: 1))
                )
            }

            // MODEL HEALTH & STATUS STRIP (Delightful & Simplified)
            modelHealthBanner

            // VOICE PRESETS CAROUSEL
            presetRackView

            Divider()
                .background(Color.white.opacity(0.08))

            // MAIN CONTROLS ROW
            HStack(alignment: .top, spacing: 12) {
                // PANEL 1: Voice Character & Details
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(SynthTheme.ledCyan)

                        Text("VOICE CHARACTER")
                            .font(.system(size: 9, weight: .bold, design: .default))
                            .foregroundColor(SynthTheme.sectionHeader)
                            .tracking(0.6)

                        Spacer()

                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                isShowingModelDetails.toggle()
                            }
                        }) {
                            HStack(spacing: 3) {
                                Text(isShowingModelDetails ? "Hide Files" : "Details")
                                    .font(.system(size: 8, weight: .semibold, design: .default))
                                Image(systemName: isShowingModelDetails ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .foregroundColor(SynthTheme.textDim)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }

                    // Character Selector Menu
                    Menu {
                        ForEach(AudioController.availableCharacters) { char in
                            Button(action: { controller.selectedCharacter = char }) {
                                HStack {
                                    Text(char.name)
                                    if controller.selectedCharacter.id == char.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(controller.selectedCharacter.name)
                                .font(.system(size: 11, weight: .semibold, design: .default))
                                .foregroundColor(SynthTheme.textBright)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(SynthTheme.textDim)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    }
                    .menuStyle(.borderlessButton)

                    Text(controller.selectedCharacter.description)
                        .font(.system(size: 8.5, weight: .regular, design: .default))
                        .foregroundColor(SynthTheme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 2)

                    // Collapsible Weight Files & Component Readiness
                    if isShowingModelDetails {
                        VStack(alignment: .leading, spacing: 4) {
                            componentStatusRow(name: "Voice Profile", file: controller.selectedCharacter.speakerEmbeddingFileName, ready: controller.loadedComponents.synth)
                            componentStatusRow(name: "Tone Checkpoint", file: "checkpoint.pth", ready: controller.loadedComponents.hubert)
                            componentStatusRow(name: "Converter Config", file: "config.json", ready: controller.loadedComponents.rmvpe)

                            HStack {
                                Spacer()
                                if controller.isDownloading {
                                    HStack(spacing: 4) {
                                        ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                                        Text(String(format: "%.0f%%", controller.downloadProgress * 100))
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .foregroundColor(SynthTheme.ledAmber)
                                        Button("Cancel") { controller.cancelDownload() }
                                            .buttonStyle(.plain)
                                            .font(.system(size: 7.5, weight: .bold))
                                            .foregroundColor(Color.red)
                                    }
                                } else {
                                    Button(action: { controller.downloadNeuralWeights() }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.triangle.2.circlepath")
                                            Text(controller.isNeuralModelLoaded ? "Verify Weights" : "Download Now")
                                        }
                                        .font(.system(size: 7.5, weight: .bold, design: .default))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(SynthTheme.ledCyan.opacity(0.15))
                                        .cornerRadius(4)
                                        .foregroundColor(SynthTheme.ledCyan)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 2)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.35))
                        .cornerRadius(6)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
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

                // PANEL 2: Performance Sliders (Pitch Shift, Index Rate, Silence Gate)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 10))
                            .foregroundColor(SynthTheme.ledAmber)

                        Text("PERFORMANCE CONTROLS")
                            .font(.system(size: 9, weight: .bold, design: .default))
                            .foregroundColor(SynthTheme.sectionHeader)
                            .tracking(0.6)
                    }

                    // Pitch Shift Slider
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Pitch Shift")
                                .font(.system(size: 8.5, weight: .semibold, design: .default))
                                .foregroundColor(SynthTheme.textDim)
                            Spacer()
                            Text(String(format: "%+.0f st", controller.pitchShiftSemitones))
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundColor(SynthTheme.ledCyan)
                        }

                        Slider(
                            value: Binding(
                                get: { controller.pitchShiftSemitones },
                                set: { controller.pitchShiftSemitones = round($0) }
                            ),
                            in: -12.0...12.0
                        )
                        .accentColor(SynthTheme.ledCyan)
                    }

                    // Tone Color Strength (Tau) Slider
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Tone Color Strength (Tau)")
                                .font(.system(size: 8.5, weight: .semibold, design: .default))
                                .foregroundColor(SynthTheme.textDim)
                            Spacer()
                            Text(String(format: "%.2f", controller.toneColorTau))
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundColor(SynthTheme.ledAmber)
                        }

                        Slider(
                            value: Binding(
                                get: { controller.toneColorTau },
                                set: { controller.toneColorTau = round($0 * 20.0) / 20.0 }
                            ),
                            in: 0.05...1.0
                        )
                        .accentColor(SynthTheme.ledAmber)
                    }

                    // Silence Gate (Noise Gate) Slider
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("Silence Gate")
                                .font(.system(size: 8.5, weight: .semibold, design: .default))
                                .foregroundColor(SynthTheme.textDim)
                            Spacer()
                            Text(controller.silenceThreshold <= 0.0001 ? "OFF" : String(format: "%.4f", controller.silenceThreshold))
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundColor(controller.silenceThreshold <= 0.0001 ? SynthTheme.textDim : SynthTheme.ledGreen)
                        }

                        Slider(
                            value: Binding(
                                get: { controller.silenceThreshold },
                                set: { controller.silenceThreshold = round($0 * 2000.0) / 2000.0 }
                            ),
                            in: 0.000...0.015
                        )
                        .accentColor(SynthTheme.ledGreen)

                        HStack(spacing: 6) {
                            Circle()
                                .fill(controller.isVoiceActive ? SynthTheme.ledGreen : Color.white.opacity(0.2))
                                .frame(width: 6, height: 6)
                                .shadow(color: controller.isVoiceActive ? SynthTheme.ledGreen.opacity(0.8) : Color.clear, radius: 3)

                            Text(controller.isVoiceActive ? "VOICE DETECTED" : "GATE CLOSED")
                                .font(.system(size: 8, weight: .bold, design: .default))
                                .foregroundColor(controller.isVoiceActive ? SynthTheme.ledGreen : SynthTheme.textDim)

                            Spacer()

                            Text(String(format: "Mic: %.4f", controller.rawInputRMS))
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(SynthTheme.textDim)
                        }
                        .padding(.top, 2)
                    }

                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
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

                // PANEL 3: I/O Level Indicators
                VStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 9))
                            .foregroundColor(SynthTheme.ledGreen)

                        Text("LEVELS")
                            .font(.system(size: 9, weight: .bold, design: .default))
                            .foregroundColor(SynthTheme.sectionHeader)
                            .tracking(0.6)
                    }

                    HStack(spacing: 14) {
                        LevelBar(title: "MIC", level: controller.inputLevel, color: SynthTheme.ledCyan)
                        LevelBar(
                            title: "VOICE",
                            level: controller.outputLevel,
                            color: controller.isNeuralModelLoaded ? SynthTheme.ledGreen : Color.red.opacity(0.3),
                            subtitle: !controller.isNeuralModelLoaded ? "MUTED" : nil
                        )
                    }
                    .padding(.top, 4)

                    Spacer(minLength: 0)
                }
                .padding(12)
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
    }

    private func componentStatusRow(name: String, file: String, ready: Bool, isOptional: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text("\(name):")
                .font(.system(size: 8, weight: .bold, design: .default))
                .foregroundColor(SynthTheme.textDim)
            Text(file)
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(SynthTheme.ledCyan)
                .lineLimit(1)
            Spacer()
            if ready {
                HStack(spacing: 3) {
                    Circle().fill(SynthTheme.ledGreen).frame(width: 4, height: 4)
                    Text("READY")
                        .font(.system(size: 7.5, weight: .bold, design: .default))
                        .foregroundColor(SynthTheme.ledGreen)
                }
            } else if isOptional {
                Text("OPTIONAL")
                    .font(.system(size: 7.5, weight: .medium, design: .default))
                    .foregroundColor(SynthTheme.textDim)
            } else {
                HStack(spacing: 3) {
                    Circle().fill(Color.red).frame(width: 4, height: 4)
                    Text("MISSING")
                        .font(.system(size: 7.5, weight: .bold, design: .default))
                        .foregroundColor(Color.red)
                }
            }
        }
    }

    // MARK: - Refined Health & Status Strip View
    @ViewBuilder
    private var modelHealthBanner: some View {
        switch controller.modelLoadStatus {
        case .ready(let charName, _, let latencyMs):
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(SynthTheme.ledGreen)
                        .frame(width: 8, height: 8)
                        .shadow(color: SynthTheme.ledGreen.opacity(0.8), radius: 4)

                    Text("OpenVoice Engine Ready")
                        .font(.system(size: 10, weight: .bold, design: .default))
                        .foregroundColor(SynthTheme.textBright)

                    Text(charName)
                        .font(.system(size: 9, weight: .semibold, design: .default))
                        .foregroundColor(SynthTheme.ledCyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(SynthTheme.ledCyan.opacity(0.12))
                        .cornerRadius(3)

                    Text("V2 TONE COLOR")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(SynthTheme.ledGreen.opacity(0.18))
                        .cornerRadius(3)
                        .foregroundColor(SynthTheme.ledGreen)

                    if latencyMs > 0 {
                        Text("\(latencyMs)ms load")
                            .font(.system(size: 8, weight: .medium, design: .default))
                            .foregroundColor(SynthTheme.textDim)
                    }

                    if controller.isSynthesizingChunk {
                        Text("• Synthesizing (\(Int(controller.lastInferenceDurationMs))ms)")
                            .font(.system(size: 8, weight: .semibold, design: .default))
                            .foregroundColor(SynthTheme.ledCyan)
                    }
                }

                Spacer()

                // Test Voice Sound Button
                HStack(spacing: 6) {
                    if let testMsg = controller.testSynthesisStatus {
                        Text(testMsg)
                            .font(.system(size: 8.5, weight: .bold, design: .default))
                            .foregroundColor(testMsg.starts(with: "✅") ? SynthTheme.ledGreen : Color.red)
                    }

                    Button(action: {
                        controller.testNeuralSynthesis()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 9))
                            Text("Test Voice")
                                .font(.system(size: 9, weight: .bold, design: .default))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(SynthTheme.ledGreen.opacity(0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(SynthTheme.ledGreen.opacity(0.6), lineWidth: 1)
                                )
                        )
                        .foregroundColor(SynthTheme.ledGreen)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )

        case .missing(let missingFiles):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color.red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Model Weights Missing")
                        .font(.system(size: 10, weight: .bold, design: .default))
                        .foregroundColor(Color.white)
                    Text("Missing: \(missingFiles.joined(separator: ", "))")
                        .font(.system(size: 8.5, weight: .regular, design: .default))
                        .foregroundColor(SynthTheme.textDim)
                }

                Spacer()

                Button(action: { controller.downloadNeuralWeights() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Download Weights")
                    }
                    .font(.system(size: 9, weight: .bold, design: .default))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.25))
                    .cornerRadius(4)
                    .foregroundColor(Color.red)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color.red.opacity(0.12))
            .cornerRadius(6)

        case .failed(let error):
            HStack(spacing: 10) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundColor(Color.red)
                Text("Model Load Error: \(error)")
                    .font(.system(size: 9, weight: .medium, design: .default))
                    .foregroundColor(Color.white)
                Spacer()
                Button("Retry") { controller.downloadNeuralWeights() }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color.red)
            }
            .padding(10)
            .background(Color.red.opacity(0.12))
            .cornerRadius(6)

        case .downloading(let progress, let fileName):
            HStack(spacing: 10) {
                ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Downloading Model Weights (\(Int(progress * 100))%)")
                        .font(.system(size: 9.5, weight: .bold, design: .default))
                        .foregroundColor(SynthTheme.ledCyan)
                    Text("Fetching: \(fileName)")
                        .font(.system(size: 8, design: .default))
                        .foregroundColor(SynthTheme.textDim)
                }
                Spacer()
                Button("Cancel") { controller.cancelDownload() }
                    .buttonStyle(.plain)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(Color.red)
            }
            .padding(9)
            .background(SynthTheme.ledCyan.opacity(0.1))
            .cornerRadius(6)

        case .loading(let charName):
            HStack(spacing: 10) {
                ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                Text("Loading OpenVoice V2 for \(charName)...")
                    .font(.system(size: 9.5, weight: .medium, design: .default))
                    .foregroundColor(SynthTheme.ledAmber)
                Spacer()
            }
            .padding(9)
            .background(SynthTheme.ledAmber.opacity(0.1))
            .cornerRadius(6)
        }
    }

    // MARK: - Voice Presets Rack View
    private var presetRackView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundColor(SynthTheme.ledAmber)

                    Text("VOICE PRESETS")
                        .font(.system(size: 9, weight: .bold, design: .default))
                        .foregroundColor(SynthTheme.sectionHeader)
                        .tracking(0.6)
                }

                Text("16 Built-in")
                    .font(.system(size: 7.5, weight: .bold, design: .default))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(SynthTheme.ledCyan.opacity(0.15))
                    .foregroundColor(SynthTheme.ledCyan)
                    .cornerRadius(3)

                if !controller.userPresets.isEmpty {
                    Text("\(controller.userPresets.count) Custom")
                        .font(.system(size: 7.5, weight: .bold, design: .default))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(SynthTheme.ledAmber.opacity(0.18))
                        .foregroundColor(SynthTheme.ledAmber)
                        .cornerRadius(3)
                }

                Spacer()

                // Save Current Voice Lab State as Preset
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        isShowingSavePresetDialog.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 9))
                        Text(isShowingSavePresetDialog ? "Cancel" : "Save Preset")
                    }
                    .font(.system(size: 8.5, weight: .bold, design: .default))
                    .foregroundColor(SynthTheme.ledAmber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(SynthTheme.ledAmber.opacity(0.15))
                            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(SynthTheme.ledAmber.opacity(0.5), lineWidth: 0.8))
                    )
                }
                .buttonStyle(.plain)
            }

            // Inline Save Dialog
            if isShowingSavePresetDialog {
                HStack(spacing: 8) {
                    TextField("Preset name...", text: $newPresetName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 9.5, design: .default))
                        .padding(5)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        .foregroundColor(.white)

                    HStack(spacing: 3) {
                        ForEach(["⭐", "🎙️", "🎩", "📻", "📞", "🤖", "🤫", "🐿️", "🎈", "👻"], id: \.self) { em in
                            Button(action: { newPresetEmoji = em }) {
                                Text(em)
                                    .font(.system(size: 11))
                                    .padding(2)
                                    .background(newPresetEmoji == em ? SynthTheme.ledCyan.opacity(0.4) : Color.clear)
                                    .cornerRadius(3)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button(action: {
                        controller.saveUserPreset(name: newPresetName, emoji: newPresetEmoji)
                        newPresetName = ""
                        isShowingSavePresetDialog = false
                    }) {
                        Text("Save")
                            .font(.system(size: 8.5, weight: .bold, design: .default))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(red: 0.1, green: 0.45, blue: 0.2))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(newPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(6)
                .background(Color.black.opacity(0.45))
                .cornerRadius(6)
            }

            // Scrollable Presets Rack
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    // Custom User Presets First
                    ForEach(controller.userPresets) { preset in
                        PresetPill(
                            preset: preset,
                            isActive: controller.selectedPresetId == preset.id,
                            isCustom: true,
                            onSelect: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    controller.applyPreset(preset)
                                }
                            },
                            onDelete: {
                                controller.deleteUserPreset(id: preset.id)
                            }
                        )
                    }

                    // Built-in Presets
                    ForEach(AudioController.builtinPresets) { preset in
                        PresetPill(
                            preset: preset,
                            isActive: controller.selectedPresetId == preset.id,
                            isCustom: false,
                            onSelect: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    controller.applyPreset(preset)
                                }
                            },
                            onDelete: nil
                        )
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }
}

private struct PresetPill: View {
    let preset: VoicePreset
    let isActive: Bool
    let isCustom: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                Text(preset.emoji)
                    .font(.system(size: 11))

                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.name)
                        .font(.system(size: 8.5, weight: isActive ? .bold : .medium, design: .default))
                        .foregroundColor(isActive ? SynthTheme.ledCyan : SynthTheme.textBright)

                    Text(String(format: "%+.0f st", preset.pitchShift))
                        .font(.system(size: 7, weight: .medium, design: .rounded))
                        .foregroundColor(SynthTheme.textDim)
                }

                if isCustom, let onDelete = onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "xmark")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundColor(Color.red.opacity(0.7))
                            .padding(2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? SynthTheme.ledCyan.opacity(0.2) : (isCustom ? SynthTheme.ledAmber.opacity(0.08) : Color.black.opacity(0.4)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isActive ? SynthTheme.ledCyan : (isCustom ? SynthTheme.ledAmber.opacity(0.4) : Color.white.opacity(0.08)), lineWidth: isActive ? 1.2 : 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .help(preset.description)
    }
}

private struct LevelBar: View {
    let title: String
    let level: Float
    let color: Color
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .default))
                .foregroundColor(SynthTheme.textDim)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 10, height: 60)

                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 10, height: CGFloat(max(0.0, min(1.0, level))) * 60)
                    .shadow(color: color.opacity(0.8), radius: 2)
            }

            if let sub = subtitle {
                Text(sub)
                    .font(.system(size: 7, weight: .bold, design: .default))
                    .foregroundColor(Color.red)
            }
        }
    }
}
