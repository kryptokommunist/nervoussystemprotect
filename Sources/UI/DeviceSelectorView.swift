import SwiftUI

public struct DeviceSelectorView: View {
    @ObservedObject public var deviceManager: AudioDeviceManager
    @ObservedObject public var audioEngine: AppAudioEngine
    @ObservedObject public var rvcController: AudioController
    public let selectedTab: Int

    public init(
        deviceManager: AudioDeviceManager,
        audioEngine: AppAudioEngine,
        rvcController: AudioController,
        selectedTab: Int
    ) {
        self.deviceManager = deviceManager
        self.audioEngine = audioEngine
        self.rvcController = rvcController
        self.selectedTab = selectedTab
    }

    public func selectInputDevice(_ dev: AudioDeviceInfo) {
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

    public func selectOutputDevice(_ dev: AudioDeviceInfo) {
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
        let currentInput = (selectedTab == 0 ? audioEngine.selectedInputDevice : rvcController.selectedInputDevice) ?? audioEngine.selectedInputDevice ?? rvcController.selectedInputDevice
        let currentOutput = (selectedTab == 0 ? audioEngine.selectedOutputDevice : rvcController.selectedOutputDevice) ?? audioEngine.selectedOutputDevice ?? rvcController.selectedOutputDevice
        let isCurrentRunning = (selectedTab == 0) ? audioEngine.isRunning : rvcController.isRunning

        HStack(spacing: 16) {
            // INPUT DEVICE PICKER
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 9))
                        .foregroundColor(SynthTheme.ledCyan)

                    Text("AUDIO SOURCE")
                        .font(.system(size: 8.5, weight: .bold, design: .default))
                        .foregroundColor(SynthTheme.textDim)
                }

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
                    HStack {
                        Text(currentInput?.name ?? "Select Input...")
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundColor(SynthTheme.textBright)
                            .lineLimit(1)
                            .truncationMode(.tail)
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
                .frame(minWidth: 220, maxWidth: 300)
            }

            // SIGNAL FLOW BRIDGE
            HStack(spacing: 4) {
                Circle()
                    .fill(isCurrentRunning ? SynthTheme.ledCyan : Color.white.opacity(0.2))
                    .frame(width: 4, height: 4)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isCurrentRunning ? SynthTheme.ledCyan : SynthTheme.textDim.opacity(0.5))
                Circle()
                    .fill(isCurrentRunning ? SynthTheme.ledGreen : Color.white.opacity(0.2))
                    .frame(width: 4, height: 4)
            }
            .padding(.top, 14)

            // OUTPUT DEVICE PICKER
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 9))
                        .foregroundColor(SynthTheme.ledGreen)

                    Text("DESTINATION")
                        .font(.system(size: 8.5, weight: .bold, design: .default))
                        .foregroundColor(SynthTheme.textDim)
                }

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
                    HStack {
                        Text(currentOutput?.name ?? "Select Output...")
                            .font(.system(size: 11, weight: .medium, design: .default))
                            .foregroundColor(SynthTheme.textBright)
                            .lineLimit(1)
                            .truncationMode(.tail)
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
                .frame(minWidth: 220, maxWidth: 300)
            }

            Spacer()

            // BYPASS & POWER SWITCHES
            HStack(spacing: 12) {
                // Bypass switch (active on Tab 0)
                if selectedTab == 0 {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            audioEngine.isBypassed.toggle()
                        }
                    }) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(audioEngine.isBypassed ? SynthTheme.ledAmber : Color.white.opacity(0.2))
                                .frame(width: 6, height: 6)
                                .shadow(color: audioEngine.isBypassed ? SynthTheme.ledAmber : Color.clear, radius: 3)

                            Text(audioEngine.isBypassed ? "BYPASS ON" : "BYPASS")
                                .font(.system(size: 9, weight: .bold, design: .default))
                                .foregroundColor(audioEngine.isBypassed ? SynthTheme.ledAmber : SynthTheme.textDim)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(audioEngine.isBypassed ? SynthTheme.ledAmber.opacity(0.18) : Color.black.opacity(0.35))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(audioEngine.isBypassed ? SynthTheme.ledAmber.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Bypass all DSP processing and pass raw audio directly")
                }

                // Master Power Switch
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if selectedTab == 0 {
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
                        } else {
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
                }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isCurrentRunning ? SynthTheme.ledGreen : Color.red.opacity(0.8))
                            .frame(width: 7, height: 7)
                            .shadow(color: isCurrentRunning ? SynthTheme.ledGreen.opacity(0.8) : Color.clear, radius: 4)

                        Text(isCurrentRunning ? "ACTIVE" : "STANDBY")
                            .font(.system(size: 9.5, weight: .bold, design: .default))
                            .foregroundColor(isCurrentRunning ? Color.white : SynthTheme.textDim)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                isCurrentRunning ?
                                LinearGradient(colors: [Color(red: 0.08, green: 0.38, blue: 0.18), Color(red: 0.05, green: 0.25, blue: 0.10)], startPoint: .top, endPoint: .bottom) :
                                LinearGradient(colors: [Color(white: 0.16), Color(white: 0.11)], startPoint: .top, endPoint: .bottom)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(isCurrentRunning ? SynthTheme.ledGreen.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
