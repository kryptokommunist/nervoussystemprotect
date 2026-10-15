import SwiftUI
import simd

/// A pure SwiftUI high-performance 3D neural network particle mesh.
/// Renders an organic, morphing geodesic neural cluster with dynamic synaptic filaments,
/// depth-shaded glowing nodes, and reactive pulsation responding to voice activity and calm levels.
public struct NeuralMeshView: View {
    public var calmLevel: Float         // 0.0 to 1.0
    public var isVoiceActive: Bool
    public var activityRMS: Float       // 0.0 to 1.0
    public var accentColor: Color

    // Precomputed 3D sphere/icosahedron cluster vertices (normalized -1.0 ... 1.0)
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

        // Subdivided midpoint neural nodes for denser synaptic cluster
        for i in 0..<icos.count {
            for j in (i + 1)..<icos.count {
                let dist = simd_distance(icos[i], icos[j])
                if dist < 2.1 {
                    let mid = simd_normalize(icos[i] + icos[j]) * 0.95
                    nodes.append(mid)
                }
            }
        }

        // Add internal core anchor nodes
        nodes.append(SIMD3<Float>(0, 0, 0))
        nodes.append(SIMD3<Float>(0.2, 0.3, -0.2))
        nodes.append(SIMD3<Float>(-0.2, -0.3, 0.2))

        return nodes
    }()

    // Precomputed connection pairs between nodes
    private static let edges: [(Int, Int)] = {
        var pairs: [(Int, Int)] = []
        let count = baseNodes.count
        for i in 0..<count {
            for j in (i + 1)..<count {
                let d = simd_distance(baseNodes[i], baseNodes[j])
                if d > 0.1 && d < 1.05 {
                    pairs.append((i, j))
                }
            }
        }
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

                // Dynamic speed and pulsation based on voice activity and calm level
                let speedMultiplier = 0.45 + Double(activityRMS) * 1.5 + (isVoiceActive ? 0.35 : 0.0)
                let angleY = Float(time * 0.65 * speedMultiplier)
                let angleX = Float(time * 0.42 * speedMultiplier)
                let angleZ = Float(time * 0.28 * speedMultiplier)

                // Organic radial breath wave
                let breath = 1.0 + 0.08 * sin(Float(time * 2.2)) + Float(activityRMS) * 0.25

                // Compute transformed 3D nodes
                var projected: [CGPoint] = []
                var depths: [Float] = [] // Z depths for depth sorting & shading

                let cosY = cos(angleY), sinY = sin(angleY)
                let cosX = cos(angleX), sinX = sin(angleX)
                let cosZ = cos(angleZ), sinZ = sin(angleZ)

                for (idx, base) in Self.baseNodes.enumerated() {
                    // Organic deformation wave per vertex
                    let wave = sin(Float(idx * 7) + Float(time * 2.5)) * 0.06
                    let r = (1.0 + wave) * breath
                    let v = base * r

                    // Rotate around Y
                    let x1 = v.x * cosY + v.z * sinY
                    let z1 = -v.x * sinY + v.z * cosY

                    // Rotate around X
                    let y2 = v.y * cosX - z1 * sinX
                    let z2 = v.y * sinX + z1 * cosX

                    // Rotate around Z
                    let x3 = x1 * cosZ - y2 * sinZ
                    let y3 = x1 * sinZ + y2 * cosZ

                    // Perspective projection
                    let cameraDist: Float = 2.8
                    let factor = cameraDist / (cameraDist + z2)
                    let screenX = center.x + CGFloat(x3 * factor * baseRadius)
                    let screenY = center.y + CGFloat(y3 * factor * baseRadius)

                    projected.append(CGPoint(x: screenX, y: screenY))
                    depths.append(z2)
                }

                // 1. Draw Synaptic Filament Edges
                for (i, j) in Self.edges {
                    let p1 = projected[i]
                    let p2 = projected[j]
                    let zAvg = (depths[i] + depths[j]) / 2.0 // -1.0 (back) to +1.0 (front)

                    // Normalized depth 0.0 to 1.0
                    let depthNorm = max(0.0, min(1.0, (zAvg + 1.2) / 2.4))
                    let edgeAlpha = Double(0.08 + depthNorm * 0.45 + (isVoiceActive ? 0.25 : 0.0))

                    var path = Path()
                    path.move(to: p1)
                    path.addLine(to: p2)

                    // Filament color gradient blend
                    let edgeColor = zAvg > 0 ?
                        accentColor.opacity(edgeAlpha) :
                        SynthTheme.ledPurple.opacity(edgeAlpha * 0.75)

                    context.stroke(
                        path,
                        with: .color(edgeColor),
                        lineWidth: CGFloat(max(0.6, depthNorm * 1.6))
                    )
                }

                // 2. Draw Glowing Neural Nodes
                for i in 0..<projected.count {
                    let pt = projected[i]
                    let z = depths[i]
                    let depthNorm = max(0.0, min(1.0, (z + 1.2) / 2.4))

                    let nodeRadius = CGFloat(1.5 + depthNorm * 3.5 + (isVoiceActive ? 1.0 : 0.0))
                    let nodeAlpha = Double(0.20 + depthNorm * 0.80)

                    // Outer soft bloom glow for foreground nodes
                    if z > -0.2 {
                        let glowRect = CGRect(
                            x: pt.x - nodeRadius * 2.2,
                            y: pt.y - nodeRadius * 2.2,
                            width: nodeRadius * 4.4,
                            height: nodeRadius * 4.4
                        )
                        let glowColor = (i % 3 == 0 ? SynthTheme.ledCyan : SynthTheme.ledAmber).opacity(nodeAlpha * 0.4)
                        context.fill(Path(ellipseIn: glowRect), with: .color(glowColor))
                    }

                    // Solid node core
                    let coreRect = CGRect(
                        x: pt.x - nodeRadius,
                        y: pt.y - nodeRadius,
                        width: nodeRadius * 2,
                        height: nodeRadius * 2
                    )

                    let coreColor = (z > 0.2 ? Color.white : accentColor).opacity(nodeAlpha)
                    context.fill(Path(ellipseIn: coreRect), with: .color(coreColor))
                }
            }
        }
        .allowsHitTesting(false) // Pure visual display
    }
}
