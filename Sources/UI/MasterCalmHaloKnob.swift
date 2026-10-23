import SwiftUI

/// An interactive, luxurious halo ring dial with an embedded live 3D neural net mesh animation.
/// Combines the tactile authority of an analog master potentiometer with a futuristic biofeedback neural core.
public struct MasterCalmHaloKnob: View {
    @Binding var value: Float            // 0.0 to 1.0 (Master Calm Level)
    var isVoiceActive: Bool
    var activityRMS: Float = 0.0
    var title: String = "MASTER CALM"
    var displayValue: String? = nil
    var accentColor: Color = SynthTheme.ledCyan
    var size: CGFloat = 190

    @StateObject private var dragState = KnobDragState()
    @State private var isHovering: Bool = false

    public init(
        value: Binding<Float>,
        isVoiceActive: Bool = false,
        activityRMS: Float = 0.0,
        title: String = "MASTER CALM",
        displayValue: String? = nil,
        accentColor: Color = SynthTheme.ledCyan,
        size: CGFloat = 190
    ) {
        self._value = value
        self.isVoiceActive = isVoiceActive
        self.activityRMS = activityRMS
        self.title = title
        self.displayValue = displayValue
        self.accentColor = accentColor
        self.size = size
    }

    // Normalized progress 0.0 ... 1.0
    private var normalizedProgress: Double {
        return Double(max(0.0, min(1.0, value)))
    }

    // Rotation angle for track from -135° to +135° (270° sweep)
    private var currentSweepAngle: Double {
        return normalizedProgress * 270.0
    }

    public var body: some View {
        VStack(spacing: 6) {
            ZStack {
                let trackDiameter = size + (size > 120 ? 18 : 12)
                let strokeWidth: CGFloat = size > 120 ? 9.0 : 5.0

                // 1. INACTIVE BACKGROUND HALO TRACK
                HaloTrackArc(startAngle: .degrees(135), endAngle: .degrees(405))
                    .stroke(
                        Color.white.opacity(0.07),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .frame(width: trackDiameter, height: trackDiameter)

                // 2. ACTIVE GLOWING EMERALD-TO-CYAN GRADIENT HALO ARC
                if normalizedProgress > 0.005 {
                    HaloTrackArc(startAngle: .degrees(135), endAngle: .degrees(135 + currentSweepAngle))
                        .stroke(
                            AngularGradient(
                                colors: [
                                    SynthTheme.ledGreen,
                                    SynthTheme.ledCyan,
                                    Color(red: 0.20, green: 0.65, blue: 0.95)
                                ],
                                center: .center,
                                startAngle: .degrees(135),
                                endAngle: .degrees(405)
                            ),
                            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                        )
                        .shadow(color: SynthTheme.ledCyan.opacity(0.7), radius: 8)
                        .frame(width: trackDiameter, height: trackDiameter)
                }

                // 3. KNOB INNER GLASS CHASSIS
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.11, green: 0.13, blue: 0.18).opacity(0.85),
                                Color(red: 0.05, green: 0.06, blue: 0.08).opacity(0.95)
                            ],
                            center: .center,
                            startRadius: 10,
                            endRadius: size / 2
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        isHovering ? Color.white.opacity(0.28) : Color.white.opacity(0.14),
                                        Color.white.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Color.black.opacity(0.55), radius: 10, x: 0, y: 5)

                // 4. EMBEDDED 3D NEURAL NET ANIMATION (Concept 3 inside Concept 4)
                NeuralMeshView(
                    calmLevel: value,
                    isVoiceActive: isVoiceActive,
                    activityRMS: activityRMS,
                    accentColor: accentColor
                )
                .frame(width: size * 0.88, height: size * 0.88)
                .opacity(0.85)

                // 5. CENTER READOUT OVERLAY (Glass HUD Badge)
                VStack(spacing: size > 100 ? 2 : 1) {
                    Text(displayValue ?? String(format: "%.0f%%", value * 100))
                        .font(.system(size: size > 140 ? (displayValue?.count ?? 0 > 4 ? 22 : 30) : (size > 90 ? 18 : 13), weight: .black, design: .rounded))
                        .foregroundColor(Color.white)
                        .shadow(color: Color.black.opacity(0.9), radius: 3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    if size > 110 {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(value > 0.01 ? SynthTheme.ledGreen : Color.white.opacity(0.3))
                                .frame(width: 5, height: 5)
                                .shadow(color: value > 0.01 ? SynthTheme.ledGreen : Color.clear, radius: 3)

                            Text(title)
                                .font(.system(size: size > 150 ? 9 : 8, weight: .bold, design: .default))
                                .foregroundColor(SynthTheme.textBright.opacity(0.9))
                                .tracking(0.8)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(4)
                    }
                }

                // 6. ROTARY POINTER NOTCH ON OUTER RIM
                Circle()
                    .fill(Color.white)
                    .frame(width: size > 100 ? 7 : 5, height: size > 100 ? 7 : 5)
                    .shadow(color: accentColor, radius: 4)
                    .offset(y: -trackDiameter / 2)
                    .rotationEffect(.degrees(-135.0 + currentSweepAngle))
            }
            .frame(width: size + 28, height: size + 28)
            .contentShape(Circle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { gesture in
                        if dragState.startValue == nil {
                            dragState.startValue = value
                        }
                        let deltaY = Float(-gesture.translation.height)
                        let sensitivity: Float = 1.0 / 180.0
                        let newValue = (dragState.startValue ?? value) + (deltaY * sensitivity)
                        value = max(0.0, min(1.0, newValue))
                    }
                    .onEnded { _ in
                        dragState.startValue = nil
                    }
            )
            .onTapGesture(count: 2) {
                // Double tap resets calm to default with spring
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    value = 0.0
                }
            }
        }
    }
}

// Circular Arc Shape for Halo Track
private struct HaloTrackArc: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}
