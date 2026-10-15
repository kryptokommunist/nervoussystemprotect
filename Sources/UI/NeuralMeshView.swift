import SwiftUI
import simd

/// A pure SwiftUI high-performance 3D neural network particle mesh.
/// Renders an organic, tranquil geodesic neural sphere with dynamic synaptic filaments,
/// depth-shaded glowing nodes, and slow meditative pulsation.
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
                let center = CGPoint(x: w / 2, y: h / 2)
                let baseRadius = Float(min(w, h) * 0.40)

                // 1. Slow, buttery, continuous celestial rotation (zero phase jumps)
                let angleY = Float(time * 0.18)                    // Smooth ~35s full orbit
                let angleX = Float(sin(time * 0.08) * 0.22)        // Soft pitch wave
                let angleZ: Float = 0.06

                // 2. Meditative resonant breathing (7.5-second slow calming cycle)
                let voiceMod = min(1.0, max(0.0, activityRMS * 2.0))
                let breath = 1.0 + 0.03 * sin(Float(time * 0.84)) + voiceMod * 0.06

                // Precompute trigonometric rotation matrix
                let cosY = cos(angleY), sinY = sin(angleY)
                let cosX = cos(angleX), sinX = sin(angleX)
                let cosZ = cos(angleZ), sinZ = sin(angleZ)

                var projected: [CGPoint] = []
                var depths: [Float] = [] // Z depths for depth-shading

                for base in Self.baseNodes {
                    let v = base * breath

                    // Rotate around Y
                    let x1 = v.x * cosY + v.z * sinY
                    let z1 = -v.x * sinY + v.z * cosY

                    // Rotate around X
                    let y2 = v.y * cosX - z1 * sinX
                    let z2 = v.y * sinX + z1 * cosX

                    // Rotate around Z
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

                // 3. Draw Synaptic Filament Edges (clean, thin, anti-aliased)
                for (i, j) in Self.edges {
                    let p1 = projected[i]
                    let p2 = projected[j]
                    let zAvg = (depths[i] + depths[j]) / 2.0 // -1.0 to +1.0

                    let isCoreEdge = (i == 12 || j == 12)
                    let depthNorm = max(0.0, min(1.0, Double((zAvg + 1.2) / 2.4)))
                    let baseAlpha = isCoreEdge ? 0.18 : (0.10 + depthNorm * 0.40)
                    let edgeAlpha = baseAlpha + (isVoiceActive ? 0.20 : 0.0)

                    var path = Path()
                    path.move(to: p1)
                    path.addLine(to: p2)

                    let edgeColor = zAvg > -0.1 ?
                        accentColor.opacity(edgeAlpha) :
                        SynthTheme.ledPurple.opacity(edgeAlpha * 0.6)

                    context.stroke(
                        path,
                        with: .color(edgeColor),
                        lineWidth: isCoreEdge ? 0.7 : CGFloat(0.7 + depthNorm * 0.9)
                    )
                }

                // 4. Draw Glowing Neural Nodes (clean, luminous, delicate)
                for i in 0..<projected.count {
                    let pt = projected[i]
                    let z = depths[i]
                    let depthNorm = max(0.0, min(1.0, Double((z + 1.2) / 2.4)))
                    let isNucleus = (i == 12)

                    let nodeRadius = isNucleus ?
                        CGFloat(3.5 + voiceMod * 2.0) :
                        CGFloat(1.6 + depthNorm * 2.4 + (isVoiceActive ? 0.8 : 0.0))

                    let nodeAlpha = isNucleus ?
                        Double(0.60 + voiceMod * 0.40) :
                        Double(0.25 + depthNorm * 0.75)

                    // Outer soft bloom glow for foreground and nucleus
                    if z > -0.1 || isNucleus {
                        let glowRadius = nodeRadius * (isNucleus ? 3.0 : 2.2)
                        let glowRect = CGRect(
                            x: pt.x - glowRadius,
                            y: pt.y - glowRadius,
                            width: glowRadius * 2,
                            height: glowRadius * 2
                        )
                        let glowColor = (isNucleus ? SynthTheme.ledCyan : (i % 2 == 0 ? accentColor : SynthTheme.ledAmber)).opacity(nodeAlpha * 0.35)
                        context.fill(Path(ellipseIn: glowRect), with: .color(glowColor))
                    }

                    // Solid node core
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
