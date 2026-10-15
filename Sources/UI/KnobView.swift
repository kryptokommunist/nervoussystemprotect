import SwiftUI

public struct KnobView: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let defaultValue: Float
    let unit: String
    let format: String
    let displayMultiplier: Float
    let isBipolar: Bool
    let accentColor: Color
    let size: CGFloat

    @StateObject private var dragState = KnobDragState()
    @State private var isHovering: Bool = false

    public init(
        title: String,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        defaultValue: Float,
        unit: String = "",
        format: String = "%.1f",
        displayMultiplier: Float = 1.0,
        isBipolar: Bool = false,
        accentColor: Color = SynthTheme.ledCyan,
        size: CGFloat = 64
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.defaultValue = defaultValue
        self.unit = unit
        self.format = format
        self.displayMultiplier = displayMultiplier
        self.isBipolar = isBipolar
        self.accentColor = accentColor
        self.size = size
    }

    // Normalized progress 0.0 to 1.0
    private var normalizedValue: Double {
        let span = Double(range.upperBound - range.lowerBound)
        guard span > 0 else { return 0 }
        let clamped = min(max(Double(value), Double(range.lowerBound)), Double(range.upperBound))
        return (clamped - Double(range.lowerBound)) / span
    }

    // Angle from -135 deg to +135 deg (270 degree rotation)
    private var currentAngle: Double {
        return -135.0 + (normalizedValue * 270.0)
    }

    // Center angle for bipolar knobs (e.g. Pitch centered at 0)
    private var zeroAngle: Double {
        if isBipolar {
            let zeroNorm = Double(0.0 - range.lowerBound) / Double(range.upperBound - range.lowerBound)
            return -135.0 + (zeroNorm * 270.0)
        } else {
            return -135.0
        }
    }

    public var body: some View {
        VStack(spacing: 5) {
            // Label Header
            Text(title.uppercased())
                .font(.system(size: size > 50 ? 9.5 : 8.5, weight: .semibold, design: .default))
                .foregroundColor(isHovering ? SynthTheme.textBright : SynthTheme.textDim)
                .tracking(0.6)
                .lineLimit(1)

            // Rotary Knob Body
            ZStack {
                let trackSize = size + (size > 50 ? 14 : 10)
                let strokeWidth: CGFloat = size > 50 ? 3.5 : 2.5

                // Inactive Background Arc Track
                KnobArc(startAngle: .degrees(135), endAngle: .degrees(405), clockwise: false)
                    .stroke(
                        Color.white.opacity(0.08),
                        style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                    )
                    .frame(width: trackSize, height: trackSize)

                // Active Glowing LED Arc Track
                if isBipolar {
                    let start = min(zeroAngle + 270, currentAngle + 270)
                    let end = max(zeroAngle + 270, currentAngle + 270)
                    KnobArc(startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
                        .stroke(
                            accentColor,
                            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                        )
                        .shadow(color: accentColor.opacity(0.6), radius: 3)
                        .frame(width: trackSize, height: trackSize)
                } else {
                    KnobArc(startAngle: .degrees(135), endAngle: .degrees(135 + (normalizedValue * 270.0)), clockwise: false)
                        .stroke(
                            accentColor,
                            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                        )
                        .shadow(color: accentColor.opacity(0.6), radius: 3)
                        .frame(width: trackSize, height: trackSize)
                }

                // Knob Center Dial Base
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                isHovering ? Color(red: 0.26, green: 0.28, blue: 0.35) : SynthTheme.knobBaseLight,
                                SynthTheme.knobBaseDark,
                                Color(red: 0.07, green: 0.08, blue: 0.10)
                            ]),
                            center: .topLeading,
                            startRadius: 2,
                            endRadius: size * 0.9
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        isHovering ? Color.white.opacity(0.3) : Color.white.opacity(0.18),
                                        Color.white.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(color: Color.black.opacity(0.5), radius: 5, x: 0, y: 3)

                // Pointer Indicator Line / Notch
                RoundedRectangle(cornerRadius: 1)
                    .fill(
                        LinearGradient(
                            colors: [Color.white, accentColor],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: max(2.0, size * 0.05), height: size * 0.30)
                    .shadow(color: accentColor.opacity(0.8), radius: 2)
                    .offset(y: -size * 0.26)
                    .rotationEffect(.degrees(currentAngle))
            }
            .frame(width: size + 16, height: size + 16)
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
                        let span = range.upperBound - range.lowerBound
                        let sensitivity: Float = span / 180.0
                        let newValue = (dragState.startValue ?? value) + (deltaY * sensitivity)
                        value = min(max(newValue, range.lowerBound), range.upperBound)
                    }
                    .onEnded { _ in
                        dragState.startValue = nil
                    }
            )
            .onTapGesture(count: 2) {
                // Double tap resets to default with a delightful spring
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    value = defaultValue
                }
            }

            // Digital LCD Readout Pill
            HStack(spacing: 2) {
                Text(String(format: format, value * displayMultiplier))
                    .font(.system(size: size > 50 ? 10.5 : 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(SynthTheme.textBright)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: size > 50 ? 8.5 : 7.5, weight: .medium, design: .default))
                        .foregroundColor(SynthTheme.textDim)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
                    )
            )
        }
    }
}

// Custom Shape for drawing the circular potentiometer arc
private struct KnobArc: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var clockwise: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: clockwise
        )
        return path
    }
}

final class KnobDragState: ObservableObject {
    var startValue: Float? = nil
}
