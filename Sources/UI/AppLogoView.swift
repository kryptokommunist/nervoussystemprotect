import SwiftUI
import AppKit

public struct AppLogoView: View {
    public var size: CGFloat
    public var showGlow: Bool

    public init(size: CGFloat = 36, showGlow: Bool = true) {
        self.size = size
        self.showGlow = showGlow
    }

    private var logoImage: NSImage? {
        if let url = Bundle.main.url(forResource: "AppLogo", withExtension: "png") ??
                     Bundle.main.resourceURL?.appendingPathComponent("AppLogo.png"),
           FileManager.default.fileExists(atPath: url.path) {
            return NSImage(contentsOf: url)
        }
        let devPath = "Resources/AppLogo.png"
        if FileManager.default.fileExists(atPath: devPath) {
            return NSImage(contentsOfFile: devPath)
        }
        return nil
    }

    public var body: some View {
        ZStack {
            if let image = logoImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(Color(red: 0.08, green: 0.09, blue: 0.12))

                    Image(systemName: "waveform.badge.shield.half.filled")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(size * 0.2)
                        .foregroundColor(SynthTheme.ledCyan)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            SynthTheme.ledCyan.opacity(0.85),
                            Color(red: 0.85, green: 0.25, blue: 0.95).opacity(0.65)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(1.0, size * 0.035)
                )
        )
        .shadow(color: showGlow ? SynthTheme.ledCyan.opacity(0.4) : Color.clear, radius: size * 0.18)
    }
}
