import SwiftUI

public struct AffectScopeView: View {
    @ObservedObject var audioEngine: AppAudioEngine
    
    // Waveform history buffers for live scope
    @State private var inputHistory: [CGFloat] = Array(repeating: 0.5, count: 52)
    @State private var outputHistory: [CGFloat] = Array(repeating: 0.5, count: 52)
    
    public init(audioEngine: AppAudioEngine) {
        self.audioEngine = audioEngine
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Screen Bezel
            ZStack(alignment: .topLeading) {
                // Background dark CRT/LCD panel with gentle radial vignette
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.04, green: 0.05, blue: 0.08),
                                Color(red: 0.02, green: 0.03, blue: 0.05)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.12), Color.white.opacity(0.03)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                
                // Subtle tranquil grid lines
                GeometryReader { geo in
                    Path { path in
                        let w = geo.size.width
                        let h = geo.size.height
                        
                        // Center horizontal baseline (calm neutral pitch)
                        path.move(to: CGPoint(x: 0, y: h * 0.45))
                        path.addLine(to: CGPoint(x: w, y: h * 0.45))
                        
                        // Upper and lower limit guidelines
                        path.move(to: CGPoint(x: 0, y: h * 0.18))
                        path.addLine(to: CGPoint(x: w, y: h * 0.18))
                        path.move(to: CGPoint(x: 0, y: h * 0.72))
                        path.addLine(to: CGPoint(x: w, y: h * 0.72))
                        
                        // Vertical division lines
                        let steps = 6
                        for s in 1..<steps {
                            let x = w * CGFloat(s) / CGFloat(steps)
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: h * 0.82))
                        }
                    }
                    .stroke(Color.white.opacity(0.04), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    
                    // Waveform Traces
                    // 1. Input Raw Emotional Pitch (Warm Amber Glow)
                    Path { path in
                        let w = geo.size.width
                        let h = geo.size.height * 0.82
                        let step = w / CGFloat(max(1, inputHistory.count - 1))
                        
                        for (idx, val) in inputHistory.enumerated() {
                            let y = h * (1.0 - val)
                            let pt = CGPoint(x: CGFloat(idx) * step, y: y)
                            if idx == 0 {
                                path.move(to: pt)
                            } else {
                                path.addLine(to: pt)
                            }
                        }
                    }
                    .stroke(
                        SynthTheme.ledAmber.opacity(0.65),
                        style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: SynthTheme.ledAmber.opacity(0.4), radius: 4)
                    
                    // 2. Neutralized Output Pitch (Soothing Cyan Glow - flattened!)
                    Path { path in
                        let w = geo.size.width
                        let h = geo.size.height * 0.82
                        let step = w / CGFloat(max(1, outputHistory.count - 1))
                        
                        for (idx, val) in outputHistory.enumerated() {
                            let y = h * (1.0 - val)
                            let pt = CGPoint(x: CGFloat(idx) * step, y: y)
                            if idx == 0 {
                                path.move(to: pt)
                            } else {
                                path.addLine(to: pt)
                            }
                        }
                    }
                    .stroke(
                        SynthTheme.ledCyan,
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: SynthTheme.ledCyan.opacity(0.7), radius: 5)
                }
                
                // Screen Header Overlays
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("AFFECT TRANSFORMATION MONITOR")
                                .font(.system(size: 8.5, weight: .bold, design: .default))
                                .foregroundColor(SynthTheme.textBright)
                            
                            Text("LIVE")
                                .font(.system(size: 7, weight: .bold, design: .default))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(SynthTheme.ledCyan.opacity(0.2))
                                .cornerRadius(3)
                                .foregroundColor(SynthTheme.ledCyan)
                        }
                        
                        HStack(spacing: 10) {
                            HStack(spacing: 4) {
                                Circle().fill(SynthTheme.ledAmber).frame(width: 5, height: 5)
                                Text("Raw Emotion")
                                    .font(.system(size: 8, weight: .medium, design: .default))
                                    .foregroundColor(SynthTheme.ledAmber)
                            }
                            
                            HStack(spacing: 4) {
                                Circle().fill(SynthTheme.ledCyan).frame(width: 5, height: 5)
                                Text("Neutralized Voice")
                                    .font(.system(size: 8, weight: .semibold, design: .default))
                                    .foregroundColor(SynthTheme.ledCyan)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Pitch Readout
                    VStack(alignment: .trailing, spacing: 2) {
                        if audioEngine.inputPitchHz > 0 {
                            Text(String(format: "IN: %.0f Hz (%+.0f¢)", audioEngine.inputPitchHz, audioEngine.pitchInflectionCents))
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundColor(SynthTheme.ledAmber)
                            
                            Text(String(format: "OUT: %.0f Hz (%+.0f¢)", audioEngine.outputPitchHz, audioEngine.flattenedInflectionCents))
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(SynthTheme.ledCyan)
                        } else {
                            Text("PITCH MONITOR: READY")
                                .font(.system(size: 8, weight: .medium, design: .default))
                                .foregroundColor(SynthTheme.textDim)
                        }
                    }
                }
                .padding(9)
                
                // Bottom Screen HUD: Dynamic Leveling Bar & Activity Badges
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        // Leveling Gain Reduction Ladder
                        HStack(spacing: 5) {
                            Text("LEVELER")
                                .font(.system(size: 7.5, weight: .bold, design: .default))
                                .foregroundColor(SynthTheme.textDim)
                            
                            LevelingMeterBar(reductionDb: audioEngine.currentGainReductionDb)
                                .frame(width: 80, height: 8)
                            
                            Text(String(format: "%+.1fdB", audioEngine.currentGainReductionDb))
                                .font(.system(size: 7.5, weight: .bold, design: .rounded))
                                .foregroundColor(audioEngine.currentGainReductionDb < -1.0 ? SynthTheme.ledAmber : SynthTheme.textDim)
                                .frame(width: 44, alignment: .leading)
                        }
                        
                        Spacer()
                        
                        // Real-time Annunciator Badges
                        HStack(spacing: 6) {
                            // Transient Softener LED
                            StatusPill(
                                title: "⚡ ATTACK SOFTENED",
                                isActive: audioEngine.transientDampedActivity > 0.15,
                                activeColor: SynthTheme.ledCyan
                            )
                            
                            // Breath Gate LED
                            StatusPill(
                                title: "💨 SIGH GATED",
                                isActive: audioEngine.breathGatedActive,
                                activeColor: SynthTheme.ledAmber
                            )
                            
                            // Urgency Notch Indicator
                            if audioEngine.urgencyBandEnergyReduction < -0.5 {
                                StatusPill(
                                    title: String(format: "🎯 3.4k NOTCH %.0fdB", audioEngine.urgencyBandEnergyReduction),
                                    isActive: true,
                                    activeColor: SynthTheme.ledGreen
                                )
                            }
                            
                            // Robot Inharmonicity Indicator
                            if audioEngine.robotInharmonicity > 0.05 || audioEngine.isRobotDrone {
                                StatusPill(
                                    title: audioEngine.isRobotDrone ? "🤖 DRONE LOCKED" : "🤖 SYNTH TIMBRE",
                                    isActive: true,
                                    activeColor: SynthTheme.ledCyan
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.bottom, 7)
                }
            }
            .frame(height: 112)
        }
        .onReceive(Timer.publish(every: 0.045, on: .main, in: .common).autoconnect()) { _ in
            updateWaveformHistory()
        }
    }
    
    private func updateWaveformHistory() {
        // Map detected pitch inflection cents (-400 to +400 cents) to 0.0 ... 1.0 (center 0.5)
        let rawNorm = CGFloat(min(1.0, max(0.0, 0.5 + Double(audioEngine.pitchInflectionCents) / 800.0)))
        let outNorm = CGFloat(min(1.0, max(0.0, 0.5 + Double(audioEngine.flattenedInflectionCents) / 800.0)))
        
        var newIn = inputHistory
        newIn.removeFirst()
        newIn.append(rawNorm)
        inputHistory = newIn
        
        var newOut = outputHistory
        newOut.removeFirst()
        newOut.append(outNorm)
        outputHistory = newOut
    }
}

// Compact horizontal gain reduction bar
private struct LevelingMeterBar: View {
    let reductionDb: Float // 0.0 down to -18.0
    let segments: Int = 10
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { idx in
                let segThreshold = -Float(idx + 1) * 1.8 // e.g. -1.8, -3.6, ... -18
                let isLit = reductionDb <= segThreshold
                let color = idx < 3 ? SynthTheme.ledGreen : (idx < 7 ? SynthTheme.ledAmber : SynthTheme.ledRed)
                
                RoundedRectangle(cornerRadius: 1)
                    .fill(isLit ? color : color.opacity(0.12))
            }
        }
        .padding(1.5)
        .background(Color.black.opacity(0.5))
        .cornerRadius(3)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }
}

// Glowing HUD Status Pill
private struct StatusPill: View {
    let title: String
    let isActive: Bool
    let activeColor: Color
    
    var body: some View {
        HStack(spacing: 3.5) {
            Circle()
                .fill(isActive ? activeColor : Color.white.opacity(0.15))
                .frame(width: 4.5, height: 4.5)
                .shadow(color: isActive ? activeColor : Color.clear, radius: 2)
            
            Text(title)
                .font(.system(size: 7.5, weight: .bold, design: .default))
                .foregroundColor(isActive ? activeColor : SynthTheme.textDim.opacity(0.6))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isActive ? activeColor.opacity(0.15) : Color.black.opacity(0.35))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(isActive ? activeColor.opacity(0.6) : Color.white.opacity(0.06), lineWidth: 0.8)
                )
        )
    }
}
