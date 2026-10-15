import SwiftUI
import AppKit

public struct StartupAbortView: View {
    @ObservedObject var healthService: StartupHealthService
    @State private var copiedNotice: Bool = false
    @State private var isRestartingDaemon: Bool = false

    public init(healthService: StartupHealthService) {
        self.healthService = healthService
    }

    public var body: some View {
        ZStack {
            SynthTheme.panelBackground
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Top Header Panel
                HStack(alignment: .center, spacing: 10) {
                    RackScrewView()

                    AppLogoView(size: 38)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("NERVOUS SYSTEM PROTECT")
                                .font(.system(size: 16, weight: .black, design: .monospaced))
                                .foregroundColor(SynthTheme.textBright)
                                .tracking(1.4)

                            Text("MODEL NSP-1")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.red.opacity(0.2))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(Color.red.opacity(0.6), lineWidth: 1)
                                        )
                                )
                                .foregroundColor(Color.red)
                        }

                        Text("STARTUP PREFLIGHT DIAGNOSTICS & SYSTEM SERVICE MONITOR")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(SynthTheme.textDim)
                            .tracking(0.8)
                    }

                    Spacer()

                    // Aborted Status Pill
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .shadow(color: Color.red, radius: 4)

                        Text("STARTUP ABORTED")
                            .font(.system(size: 9.5, weight: .black, design: .monospaced))
                            .foregroundColor(Color.red)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.red.opacity(0.5), lineWidth: 1))
                    .cornerRadius(4)

                    RackScrewView()
                        .padding(.leading, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)

                // Critical Alert Banner
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Color.red)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("CRITICAL AUDIO SUBSYSTEM FAILURE DETECTED")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .tracking(0.6)

                        if let err = healthService.fatalError {
                            Text(err.localizedDescription)
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("A required system audio service is unresponsive or missing. Startup was aborted to protect system stability.")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.85))
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 0.35, green: 0.08, blue: 0.08))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.6), lineWidth: 1.2))
                )
                .padding(.horizontal, 16)

                // Service Health Checklist Table
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("SERVICE PREFLIGHT HEALTH MATRIX")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(SynthTheme.sectionHeader)
                            .tracking(0.8)

                        Spacer()

                        Text("REQUIRED FOR REALTIME AUDIO DSP")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(SynthTheme.textDim)
                    }
                    .padding(.bottom, 2)

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 6) {
                            ForEach(healthService.services) { service in
                                serviceRow(service)
                            }
                        }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(SynthTheme.panelPlate)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(SynthTheme.panelBorder, lineWidth: 1))
                )
                .padding(.horizontal, 16)

                Spacer(minLength: 6)

                // Action Bar
                HStack(spacing: 12) {
                    // Quit / Abort Button
                    Button(action: {
                        NSApplication.shared.terminate(nil)
                        exit(1)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.octagon.fill")
                            Text("ABORT & QUIT")
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.red.opacity(0.85))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.red, lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)

                    // Copy 'sudo killall coreaudiod' button
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("sudo killall coreaudiod", forType: .string)
                        copiedNotice = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            copiedNotice = false
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: copiedNotice ? "checkmark" : "doc.on.doc")
                            Text(copiedNotice ? "COMMAND COPIED!" : "COPY 'sudo killall coreaudiod'")
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(copiedNotice ? SynthTheme.ledGreen : SynthTheme.ledAmber)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SynthTheme.ledAmber.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(SynthTheme.ledAmber.opacity(0.5), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)

                    // AppleScript daemon restart button
                    Button(action: {
                        restartCoreAudioWithPrivileges()
                    }) {
                        HStack(spacing: 6) {
                            if isRestartingDaemon {
                                ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                                Text("RESTARTING...")
                            } else {
                                Image(systemName: "bolt.fill")
                                Text("RESTART COREAUDIOD (ADMIN)")
                            }
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(SynthTheme.ledCyan)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SynthTheme.ledCyan.opacity(0.12))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(SynthTheme.ledCyan.opacity(0.5), lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRestartingDaemon)

                    Spacer()

                    // Retry Preflight Button
                    Button(action: {
                        healthService.runPreflight()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("RETRY PREFLIGHT")
                        }
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(SynthTheme.ledGreen.opacity(0.8))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(SynthTheme.ledGreen, lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)

                // Bottom Status Footer & Rack Screws
                HStack(alignment: .center) {
                    RackScrewView()

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundColor(SynthTheme.textDim)

                        Text("If coreaudiod is stuck, macOS audio IPC is blocked. Restarting coreaudiod resets the audio daemon safely.")
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundColor(SynthTheme.textDim)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.leading, 8)

                    Spacer(minLength: 12)

                    Text("STATUS: STARTUP BLOCKED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.red.opacity(0.9))
                        .layoutPriority(1)

                    RackScrewView()
                        .padding(.leading, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .frame(minWidth: 880, idealWidth: 900, minHeight: 560, idealHeight: 570)
    }

    private func serviceRow(_ service: StartupServiceItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // Status Icon
            Group {
                switch service.status {
                case .healthy:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(SynthTheme.ledGreen)
                case .warning:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(SynthTheme.ledAmber)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(Color.red)
                case .checking:
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                case .pending:
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 10, height: 10)
                }
            }
            .font(.system(size: 13, weight: .bold))
            .frame(width: 18)

            // Service Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(service.name)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(SynthTheme.textBright)

                    if service.isFatal {
                        Text("CRITICAL")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.25))
                            .foregroundColor(Color.red)
                            .cornerRadius(2)
                    }
                }

                Text(service.details)
                    .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                    .foregroundColor(service.status == .failed ? Color.red.opacity(0.9) : SynthTheme.textDim)

                if let r = service.remedy, service.status == .failed {
                    Text("Remedy: \(r)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(SynthTheme.ledAmber)
                }
            }

            Spacer()

            // Status Badge
            statusBadge(service.status)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(service.status == .failed ? Color.red.opacity(0.1) : Color.black.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(service.status == .failed ? Color.red.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 0.8)
                )
        )
    }

    private func statusBadge(_ status: StartupServiceItem.Status) -> some View {
        let (label, bg, fg) = badgeAttributes(for: status)
        return Text(label)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(bg)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(fg.opacity(0.6), lineWidth: 0.8))
            )
            .foregroundColor(fg)
    }

    private func badgeAttributes(for status: StartupServiceItem.Status) -> (String, Color, Color) {
        switch status {
        case .healthy:
            return ("HEALTHY", SynthTheme.ledGreen.opacity(0.15), SynthTheme.ledGreen)
        case .warning:
            return ("WARNING", SynthTheme.ledAmber.opacity(0.15), SynthTheme.ledAmber)
        case .failed:
            return ("FAILED / STUCK", Color.red.opacity(0.25), Color.red)
        case .checking:
            return ("CHECKING...", SynthTheme.ledCyan.opacity(0.15), SynthTheme.ledCyan)
        case .pending:
            return ("PENDING", Color.white.opacity(0.1), SynthTheme.textDim)
        }
    }

    private func restartCoreAudioWithPrivileges() {
        isRestartingDaemon = true
        DispatchQueue.global(qos: .userInitiated).async {
            let script = "do shell script \"killall coreaudiod\" with administrator privileges"
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
            }
            DispatchQueue.main.async {
                self.isRestartingDaemon = false
                // Wait 1.5 seconds for coreaudiod to respawn
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    self.healthService.runPreflight()
                }
            }
        }
    }
}

public struct StartupProgressView: View {
    @ObservedObject var healthService: StartupHealthService

    public init(healthService: StartupHealthService) {
        self.healthService = healthService
    }

    public var body: some View {
        ZStack {
            SynthTheme.panelBackground
                .ignoresSafeArea()

            VStack(spacing: 20) {
                RackScrewView()

                Spacer()

                AppLogoView(size: 54)

                VStack(spacing: 8) {
                    Text("NERVOUS SYSTEM PROTECT")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .foregroundColor(SynthTheme.textBright)
                        .tracking(1.6)

                    Text("MODEL NSP-1 • STARTUP SERVICE PREFLIGHT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(SynthTheme.ledCyan)
                        .tracking(1.0)
                }

                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)

                    Text("Verifying audio drivers, permissions & neural engine...")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(SynthTheme.textDim)
                }
                .padding(.top, 10)

                Spacer()

                RackScrewView()
            }
            .padding(24)
        }
        .frame(minWidth: 880, idealWidth: 900, minHeight: 560, idealHeight: 570)
    }
}
