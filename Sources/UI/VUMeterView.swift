import SwiftUI

public struct VUMeterView: View {
    let leftLevel: Float   // 0.0 to 1.0
    let rightLevel: Float  // 0.0 to 1.0
    let segmentCount: Int = 16

    public init(leftLevel: Float, rightLevel: Float) {
        self.leftLevel = leftLevel
        self.rightLevel = rightLevel
    }

    public var body: some View {
        VStack(spacing: 6) {
            Text("OUTPUT VU")
                .font(.system(size: 8.5, weight: .bold, design: .default))
                .foregroundColor(SynthTheme.textDim)
                .tracking(0.8)

            HStack(spacing: 8) {
                // dB Scale markings
                VStack(alignment: .trailing, spacing: 0) {
                    Text("+3").font(.system(size: 7.5, weight: .bold, design: .rounded)).foregroundColor(SynthTheme.ledRed)
                    Spacer()
                    Text(" 0").font(.system(size: 7.5, weight: .bold, design: .rounded)).foregroundColor(SynthTheme.ledAmber)
                    Spacer()
                    Text("-6").font(.system(size: 7.5, weight: .medium, design: .rounded)).foregroundColor(SynthTheme.ledGreen)
                    Spacer()
                    Text("-18").font(.system(size: 7.5, weight: .regular, design: .rounded)).foregroundColor(SynthTheme.textDim)
                }
                .frame(height: 96)

                // Left Meter
                VStack(spacing: 3) {
                    MeterBar(level: leftLevel, segmentCount: segmentCount)
                    Text("L")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(SynthTheme.textDim)
                }

                // Right Meter
                VStack(spacing: 3) {
                    MeterBar(level: rightLevel, segmentCount: segmentCount)
                    Text("R")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(SynthTheme.textDim)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }
}

private struct MeterBar: View {
    let level: Float
    let segmentCount: Int

    var body: some View {
        VStack(spacing: 2) {
            ForEach((0..<segmentCount).reversed(), id: \.self) { index in
                let threshold = Float(index) / Float(segmentCount)
                let isActive = level >= threshold
                let color = segmentColor(for: index)

                RoundedRectangle(cornerRadius: 1)
                    .fill(isActive ? color : color.opacity(0.12))
                    .frame(width: 14, height: 4)
                    .shadow(color: isActive ? color.opacity(0.7) : Color.clear, radius: 2)
            }
        }
    }

    private func segmentColor(for index: Int) -> Color {
        if index >= 14 {
            return SynthTheme.ledRed
        } else if index >= 10 {
            return SynthTheme.ledAmber
        } else {
            return SynthTheme.ledGreen
        }
    }
}
