import SwiftUI

public struct SynthTheme {
    // Chassis & faceplate - Luxurious modern obsidian & slate studio styling
    public static let panelBackground = Color(red: 0.06, green: 0.07, blue: 0.09)
    public static let panelPlate = Color(red: 0.10, green: 0.11, blue: 0.15)
    public static let panelPlateElevated = Color(red: 0.13, green: 0.15, blue: 0.20)
    public static let panelBorder = Color(white: 1.0).opacity(0.08)
    public static let panelBorderSubtle = Color(white: 1.0).opacity(0.04)
    public static let sectionHeader = Color(red: 0.90, green: 0.92, blue: 0.96)
    
    // Accents & LEDs
    public static let ledAmber = Color(red: 1.0, green: 0.70, blue: 0.24)
    public static let ledAmberGlow = Color(red: 1.0, green: 0.70, blue: 0.24).opacity(0.35)
    public static let ledCyan = Color(red: 0.18, green: 0.84, blue: 0.92)
    public static let ledCyanGlow = Color(red: 0.18, green: 0.84, blue: 0.92).opacity(0.35)
    public static let ledGreen = Color(red: 0.24, green: 0.88, blue: 0.55)
    public static let ledGreenGlow = Color(red: 0.24, green: 0.88, blue: 0.55).opacity(0.35)
    public static let ledRed = Color(red: 0.98, green: 0.35, blue: 0.38)
    public static let ledPurple = Color(red: 0.68, green: 0.46, blue: 0.98)
    
    // Knobs & Hardware
    public static let knobBaseDark = Color(red: 0.12, green: 0.13, blue: 0.17)
    public static let knobBaseLight = Color(red: 0.22, green: 0.24, blue: 0.30)
    public static let knobRim = Color(red: 0.35, green: 0.38, blue: 0.46)
    public static let textDim = Color(red: 0.55, green: 0.58, blue: 0.66)
    public static let textMuted = Color(red: 0.40, green: 0.43, blue: 0.50)
    public static let textBright = Color(red: 0.95, green: 0.96, blue: 0.98)
}

// Background Card Styling helper
public struct StudioCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 10
    var elevated: Bool = false
    
    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: elevated ? [
                                SynthTheme.panelPlateElevated,
                                SynthTheme.panelPlate
                            ] : [
                                SynthTheme.panelPlate,
                                Color(red: 0.08, green: 0.09, blue: 0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.12),
                                        Color.white.opacity(0.03)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 3)
            )
    }
}

public extension View {
    func studioCard(cornerRadius: CGFloat = 10, elevated: Bool = false) -> some View {
        modifier(StudioCardModifier(cornerRadius: cornerRadius, elevated: elevated))
    }
}

// Visual Rack Screw - retained for compatibility, styled minimally
public struct RackScrewView: View {
    public init() {}
    public var body: some View {
        // Intentionally ultra-minimal or empty for modern clean look
        Circle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 5, height: 5)
    }
}
