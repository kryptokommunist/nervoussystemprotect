import SwiftUI
import simd

/// A pure SwiftUI high-performance 3D neural network particle mesh.
/// Renders an organic, tranquil geodesic neural sphere with dynamic synaptic filaments,
/// depth-shaded glowing nodes, independent 3D harmonic node wandering, and sound-matched acoustic pulsation.
public struct NeuralMeshView: View {
    public var calmLevel: Float         // 0.0 to 1.0
    public var isVoiceActive: Bool
    public var activityRMS: Float       // 0.0 to 1.0
    public var accentColor: Color

    // Sacred-geometry icosahedron vertices (12 vertices normalized to unit sphere) + 1 center nucleus
    private static let baseNodes: [SIMD3<Float>] = {
        var nodes: [SIMD3<Float>] = []
        let phi: Float = (1.0 + sqrt(5.0)) / 2.0 // Golden ratio

        // 12 icosahedron vertices
        let icos: [SIMD3<Float>] = [
            SIMD3<Float>(-1, phi, 0), SIMD3<Float>(1, phi, 0),
            SIMD3<Float>(-1, -phi, 0), SIMD3<Float>(1, -phi, 0),
            SIMD3<Float>(0, -1, phi), SIMD3<Float>(0, 1, phi),
            SIMD3<Float>(0, -1, -phi), SIMD3<Float>(0, 1, -phi),
            SIMD3<Float>(phi, 0, -1), SIMD3<Float>(phi, 0, 1),
            SIMD3<Float>(-phi, 0, -1), SIMD3<Float>(-phi, 0, 1)
        ]

        for v in icos {
            nodes.append(simd_normalize(v))
        }

        // 13th node: Luminous central nucleus
        nodes.append(SIMD3<Float>(0, 0, 0))

        return nodes
    }()

    // 30 golden-ratio geodesic surface edges + 4 core synaptic connections
    private static let edges: [(Int, Int)] = {
        var pairs: [(Int, Int)] = []
        let count = 12
        for i in 0..<count {
            for j in (i + 1)..<count {
                let d = simd_distance(baseNodes[i], baseNodes[j])
                // Icosahedron edge length is ~1.051
                if d < 1.15 {
                    pairs.append((i, j))
                }
            }
        }
        // Connect nucleus (index 12) to select vertices for depth
        pairs.append((12, 0))
        pairs.append((12, 3))
        pairs.append((12, 5))
        pairs.append((12, 8))
        return pairs
    }()

    public init(
        calmLevel: Float = 0.5,
        isVoiceActive: Bool = false,
        activityRMS: Float = 0.0,
        accentColor: Color = SynthTheme.ledCyan
    ) {
        self.calmLevel = calmLevel
        self.isVoiceActive = isVoiceActive
        self.activityRMS = activityRMS
        self.accentColor = accentColor
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let w = size.width
                let h = size.height

                // Sound energy excitation (0.0 to 1.0)
                let soundEnergy: Float = min(1.0, max(0.0, activityRMS * 2.2))
                let t: Double = time

                // 1. Slow, organic 3D space movement: Continuous celestial rotation & buoyant drift
                let rotYBase: Double = t * 0.12
                let rotYSound: Double = Double(soundEnergy) * sin(t * 0.6) * 0.05
                let angleY = Float(rotYBase + rotYSound)

                let pitch1: Double = sin(t * 0.07) * 0.26
                let pitch2: Double = cos(t * 0.04) * 0.12
                let angleX = Float(pitch1 + pitch2)

                let angleZ = Float(cos(t * 0.05) * 0.15)

                // Buoyant zero-gravity spatial bobbing
                let bobX1: Double = sin(t * 0.22) * 3.5
                let bobX2: Double = cos(t * 0.13) * 1.5
                let driftX = CGFloat(bobX1 + bobX2)

                let bobY1: Double = cos(t * 0.18) * 3.0
                let bobY2: Double = sin(t * 0.27) * 1.2
                let driftY = CGFloat(bobY1 + bobY2)

                let center = CGPoint(x: w / 2 + driftX, y: h / 2 + driftY)
                let minDim = Float(min(w, h))
                let baseRadius: Float = minDim * 0.38

                // 2. Meditative resonant breathing matched to sound
                let breathWave: Float = 0.035 * sin(Float(t * 0.82))
                let breathSound: Float = soundEnergy * 0.16
                let breath: Float = 1.0 + breathWave + breathSound

                // Precompute trigonometric rotation matrix
                let cosY = cos(angleY), sinY = sin(angleY)
                let cosX = cos(angleX), sinX = sin(angleX)
                let cosZ = cos(angleZ), sinZ = sin(angleZ)

                var projected: [CGPoint] = []
                var depths: [Float] = [] // Z depths for depth-shading

                for i in 0..<Self.baseNodes.count {
                    let base = Self.baseNodes[i]
                    let isNucleus = (i == 12)
                    let phase = Float(i) * 1.6180339887

                    // 3. Nodes moving around slightly (harmonic 3D wandering)
                    var nodePos: SIMD3<Float>
                    if isNucleus {
                        // Gentle nucleus floating drift
                        let nx: Float = sin(Float(t * 0.25)) * 0.04
                        let ny: Float = cos(Float(t * 0.20)) * 0.04
                        let nz: Float = sin(Float(t * 0.30)) * 0.04
                        nodePos = SIMD3<Float>(nx, ny, nz)
                    } else {
                        // Independent harmonic 3D wandering for outer nodes
                        let wx1: Float = sin(Float(t * 0.35) + phase * 2.1) * 0.065
                        let wx2: Float = cos(Float(t * 0.21) + phase * 0.9) * 0.035
                        let wanderX: Float = wx1 + wx2

                        let wy1: Float = cos(Float(t * 0.31) + phase * 1.7) * 0.065
                        let wy2: Float = sin(Float(t * 0.18) + phase * 1.3) * 0.035
                        let wanderY: Float = wy1 + wy2

                        let wz1: Float = sin(Float(t * 0.42) + phase * 3.2) * 0.065
                        let wz2: Float = cos(Float(t * 0.25) + phase * 2.4) * 0.035
                        let wanderZ: Float = wz1 + wz2

                        let wander = SIMD3<Float>(wanderX, wanderY, wanderZ)

                        // Subtle acoustic vibration excitement matched to sound
                        let vibeOsc: Float = sin(Float(t * 7.5) + phase * 3.0)
                        let acousticVibe: Float = soundEnergy * 0.06 * vibeOsc
                        let localScale: Float = breath + acousticVibe

                        let shifted = base + wander
                        nodePos = shifted * localScale
                    }

                    // 3D Matrix Rotation (Yaw -> Pitch -> Roll)
                    let x1 = nodePos.x * cosY + nodePos.z * sinY
                    let z1 = -nodePos.x * sinY + nodePos.z * cosY

                    let y2 = nodePos.y * cosX - z1 * sinX
                    let z2 = nodePos.y * sinX + z1 * cosX

                    let x3 = x1 * cosZ - y2 * sinZ
                    let y3 = x1 * sinZ + y2 * cosZ

                    // Perspective projection (camera distance 3.2 for soft telephoto depth)
                    let cameraDist: Float = 3.2
                    let factor = cameraDist / (cameraDist + z2)
                    let screenX = center.x + CGFloat(x3 * factor * baseRadius)
                    let screenY = center.y + CGFloat(y3 * factor * baseRadius)

                    projected.append(CGPoint(x: screenX, y: screenY))
                    depths.append(z2)
                }

                // 4. Draw Synaptic Filament Edges (clean, organic, flexing with wandering nodes)
                for (edgeIndex, (i, j)) in Self.edges.enumerated() {
                    let p1 = projected[i]
                    let p2 = projected[j]
                    let zAvg = (depths[i] + depths[j]) / 2.0

                    let isCoreEdge = (i == 12 || j == 12)
                    let depthNorm: Double = max(0.0, min(1.0, Double((zAvg + 1.2) / 2.4)))
                    let baseAlpha: Double = isCoreEdge ? 0.20 : (0.10 + depthNorm * 0.38)
                    let voiceBoost: Double = isVoiceActive ? 0.15 : 0.0
                    let soundBoost: Double = Double(soundEnergy) * 0.32
                    let edgeAlpha: Double = baseAlpha + voiceBoost + soundBoost

                    var path = Path()
                    path.move(to: p1)
                    path.addLine(to: p2)

                    let edgeColor = zAvg > -0.1 ?
                        accentColor.opacity(min(1.0, edgeAlpha)) :
                        SynthTheme.ledPurple.opacity(min(1.0, edgeAlpha * 0.65))

                    let strokeWidth: CGFloat
                    if isCoreEdge {
                        strokeWidth = CGFloat(0.8 + soundEnergy * 0.6)
                    } else {
                        strokeWidth = CGFloat(0.7 + Float(depthNorm) * 0.9 + soundEnergy * 0.5)
                    }

                    context.stroke(
                        path,
                        with: .color(edgeColor),
                        lineWidth: strokeWidth
                    )

                    // 5. Traveling Synaptic Energy Sparks along Core Filaments (matched to sound)
                    if isCoreEdge {
                        let sparkSpeed: Double = 0.5 + Double(soundEnergy) * 0.9
                        let edgePhase: Double = Double(edgeIndex) * 0.25
                        let sparkProgress: Double = (t * sparkSpeed + edgePhase).truncatingRemainder(dividingBy: 1.0)
                        let tSpark = CGFloat(sparkProgress)
                        let sparkX: CGFloat = p1.x + (p2.x - p1.x) * tSpark
                        let sparkY: CGFloat = p1.y + (p2.y - p1.y) * tSpark

                        let sparkRadius: CGFloat = CGFloat(1.5 + soundEnergy * 2.0)
                        let sparkAlpha: Double = (0.35 + Double(soundEnergy) * 0.55) * sin(sparkProgress * .pi)
                        let sparkRect = CGRect(x: sparkX - sparkRadius, y: sparkY - sparkRadius, width: sparkRadius * 2, height: sparkRadius * 2)

                        context.fill(Path(ellipseIn: sparkRect), with: .color(accentColor.opacity(max(0.0, min(1.0, sparkAlpha)))))
                    }
                }

                // 6. Draw Glowing Neural Nodes (luminous, depth-shaded, pulsing with sound)
                for i in 0..<projected.count {
                    let pt = projected[i]
                    let z = depths[i]
                    let depthNorm: Double = max(0.0, min(1.0, Double((z + 1.2) / 2.4)))
                    let isNucleus = (i == 12)

                    let nodeRadius: CGFloat
                    if isNucleus {
                        nodeRadius = CGFloat(3.5 + soundEnergy * 3.5)
                    } else {
                        let voiceBonus: CGFloat = isVoiceActive ? 0.8 : 0.0
                        nodeRadius = CGFloat(1.6 + depthNorm * 2.4) + voiceBonus + CGFloat(soundEnergy * 1.0)
                    }

                    let nodeAlpha: Double = isNucleus ?
                        (0.65 + Double(soundEnergy) * 0.35) :
                        (0.25 + depthNorm * 0.75)

                    // Outer soft bloom glow for foreground nodes and central nucleus
                    if z > -0.1 || isNucleus {
                        let glowMultiplier: CGFloat = isNucleus ? (2.8 + CGFloat(soundEnergy) * 1.5) : 2.2
                        let glowRadius = nodeRadius * glowMultiplier
                        let glowRect = CGRect(
                            x: pt.x - glowRadius,
                            y: pt.y - glowRadius,
                            width: glowRadius * 2,
                            height: glowRadius * 2
                        )
                        let glowColor = (isNucleus ? SynthTheme.ledCyan : (i % 2 == 0 ? accentColor : SynthTheme.ledAmber)).opacity(nodeAlpha * 0.35)
                        context.fill(Path(ellipseIn: glowRect), with: .color(glowColor))
                    }

                    // Solid luminous node core
                    let coreRect = CGRect(
                        x: pt.x - nodeRadius,
                        y: pt.y - nodeRadius,
                        width: nodeRadius * 2,
                        height: nodeRadius * 2
                    )

                    let coreColor = (z > 0.3 || isNucleus ? Color.white : accentColor).opacity(nodeAlpha)
                    context.fill(Path(ellipseIn: coreRect), with: .color(coreColor))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
