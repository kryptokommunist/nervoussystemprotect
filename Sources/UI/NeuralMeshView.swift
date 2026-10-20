import SwiftUI
import AppKit
import simd

/// Tracks normalized mouse coordinates (-1...1, -1...1) across the active UI window
/// in both Compact Zen HUD (small) and Expanded Studio modes without intercepting hit-testing.
public final class NeuralMouseTracker {
    public static let shared = NeuralMouseTracker()

    public struct MouseRotationState {
        public var normX: Float       // -1.0 (left) ... +1.0 (right)
        public var normY: Float       // -1.0 (top)  ... +1.0 (bottom)
        public var influence: Float   // 0.0 (off UI) ... 1.0 (on UI)
    }

    private var viewSize: CGSize = .zero
    private var targetNormX: Float = 0.0
    private var targetNormY: Float = 0.0
    private var isMouseOnUI: Bool = false
    private var lastHoverActiveTime: TimeInterval = 0.0

    private var smoothedNormX: Float = 0.0
    private var smoothedNormY: Float = 0.0
    private var smoothedInfluence: Float = 0.0
    private var lastSampleTime: TimeInterval = 0.0
    private var eventMonitor: Any?

    private init() {
        setupEventMonitor()
    }

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .mouseEntered, .mouseExited]
        ) { [weak self] event in
            self?.handleAppKitEvent(event)
            return event
        }
    }

    private func handleAppKitEvent(_ event: NSEvent) {
        guard let window = event.window ?? Self.findActiveUIWindow(),
              let contentView = window.contentView else { return }

        let bounds = contentView.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }

        let locInWindow = window.mouseLocationOutsideOfEventStream
        let loc = contentView.convert(locInWindow, from: nil)

        if bounds.contains(loc) && event.type != .mouseExited {
            let nx = Float((loc.x / bounds.width) * 2.0 - 1.0)
            let ny = Float(1.0 - (loc.y / bounds.height) * 2.0)
            targetNormX = max(-1.0, min(1.0, nx))
            targetNormY = max(-1.0, min(1.0, ny))
            isMouseOnUI = true
            lastHoverActiveTime = Date().timeIntervalSinceReferenceDate
        } else if event.type == .mouseExited {
            isMouseOnUI = false
        }
    }

    public func updateViewSize(_ size: CGSize) {
        if size.width > 1 && size.height > 1 {
            viewSize = size
        }
    }

    public func updateHover(location: CGPoint?, isInside: Bool) {
        if isInside, let loc = location, viewSize.width > 1, viewSize.height > 1 {
            let nx = Float((loc.x / viewSize.width) * 2.0 - 1.0)
            let ny = Float((loc.y / viewSize.height) * 2.0 - 1.0)
            targetNormX = max(-1.0, min(1.0, nx))
            targetNormY = max(-1.0, min(1.0, ny))
            isMouseOnUI = true
            lastHoverActiveTime = Date().timeIntervalSinceReferenceDate
        } else if !isInside {
            isMouseOnUI = false
        }
    }

    private static func findActiveUIWindow() -> NSWindow? {
        return NSApplication.shared.windows.first(where: {
            $0.isVisible && $0.contentView != nil && $0.frame.width >= 300
        }) ?? NSApplication.shared.keyWindow
    }

    private func pollWindowMouseLocation(now: TimeInterval) {
        guard let window = Self.findActiveUIWindow(),
              let contentView = window.contentView else { return }

        let bounds = contentView.bounds
        guard bounds.width > 1, bounds.height > 1 else { return }

        let locInWindow = window.mouseLocationOutsideOfEventStream
        let loc = contentView.convert(locInWindow, from: nil)

        if bounds.contains(loc) {
            let nx = Float((loc.x / bounds.width) * 2.0 - 1.0)
            let ny = Float(1.0 - (loc.y / bounds.height) * 2.0)
            targetNormX = max(-1.0, min(1.0, nx))
            targetNormY = max(-1.0, min(1.0, ny))
            isMouseOnUI = true
            lastHoverActiveTime = now
        } else if now - lastHoverActiveTime > 0.08 {
            isMouseOnUI = false
        }
    }

    public func sampleState(time: TimeInterval) -> MouseRotationState {
        let dt: Float
        if lastSampleTime == 0.0 {
            dt = 1.0 / 60.0
            lastSampleTime = time
        } else {
            let rawDt = time - lastSampleTime
            if rawDt < 0.001 {
                return MouseRotationState(
                    normX: smoothedNormX,
                    normY: smoothedNormY,
                    influence: smoothedInfluence
                )
            }
            dt = Float(min(0.1, max(0.001, rawDt)))
            lastSampleTime = time
        }

        pollWindowMouseLocation(now: time)

        let targetInfluence: Float = isMouseOnUI ? 1.0 : 0.0
        let influenceRate: Float = isMouseOnUI ? 14.0 : 4.0
        let influenceAlpha = 1.0 - exp(-influenceRate * dt)
        smoothedInfluence += (targetInfluence - smoothedInfluence) * influenceAlpha

        let posAlpha = 1.0 - exp(-18.0 * dt)
        smoothedNormX += (targetNormX - smoothedNormX) * posAlpha
        smoothedNormY += (targetNormY - smoothedNormY) * posAlpha

        return MouseRotationState(
            normX: smoothedNormX,
            normY: smoothedNormY,
            influence: smoothedInfluence
        )
    }
}

public extension View {
    /// Attaches continuous mouse position tracking across a UI root view (both Compact HUD and Expanded Studio modes)
    /// so any embedded `NeuralMeshView` maps its 3D rotation to the mouse cursor.
    func trackMouseForNeuralMesh() -> some View {
        self.background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        NeuralMouseTracker.shared.updateViewSize(geo.size)
                    }
                    .onChange(of: geo.size) { _, newSize in
                        NeuralMouseTracker.shared.updateViewSize(newSize)
                    }
            }
        )
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let location):
                NeuralMouseTracker.shared.updateHover(location: location, isInside: true)
            case .ended:
                NeuralMouseTracker.shared.updateHover(location: nil, isInside: false)
            }
        }
    }
}

/// A pure SwiftUI high-performance 3D neural network particle mesh.
/// Renders an organic, tranquil geodesic neural sphere with dynamic synaptic filaments,
/// depth-shaded glowing nodes, independent 3D harmonic node wandering, sound-matched acoustic pulsation,
/// and interactive 3D rotation mapped onto mouse movement across the UI.
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

    private static func shortestAngleLerp(_ a: Float, _ b: Float, t: Float) -> Float {
        var diff = (b - a).truncatingRemainder(dividingBy: 2.0 * .pi)
        if diff > .pi { diff -= 2.0 * .pi }
        if diff < -.pi { diff += 2.0 * .pi }
        return a + diff * t
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

                // Sample live mouse rotation state across the UI (both Compact HUD & Expanded Studio modes)
                let mouseState = NeuralMouseTracker.shared.sampleState(time: t)
                let inf = mouseState.influence

                // 1. 3D space rotation: Mapped onto mouse position while cursor is on the UI,
                // smoothly blending with ambient celestial drift when cursor leaves the UI.
                let rotYBase: Double = (t * 0.12).truncatingRemainder(dividingBy: 2.0 * .pi)
                let rotYSound: Double = Double(soundEnergy) * sin(t * 0.6) * 0.05
                let ambientAngleY = Float(rotYBase + rotYSound)

                let pitch1: Double = sin(t * 0.07) * 0.26
                let pitch2: Double = cos(t * 0.04) * 0.12
                let ambientAngleX = Float(pitch1 + pitch2)
                let ambientAngleZ = Float(cos(t * 0.05) * 0.15)

                // Mouse-mapped 3D rotation angles (Yaw from X, Pitch from Y, Roll from diagonal)
                let mouseAngleY: Float = mouseState.normX * (.pi * 0.85) + Float(rotYSound)
                let mouseAngleX: Float = -mouseState.normY * (.pi * 0.65)
                let mouseAngleZ: Float = (mouseState.normX * mouseState.normY * 0.40) + (mouseState.normX * 0.15)

                let angleY = Self.shortestAngleLerp(ambientAngleY, mouseAngleY, t: inf)
                let angleX = Self.shortestAngleLerp(ambientAngleX, mouseAngleX, t: inf)
                let angleZ = Self.shortestAngleLerp(ambientAngleZ, mouseAngleZ, t: inf)

                // Buoyant zero-gravity spatial bobbing + subtle cursor parallax
                let bobX1: Double = sin(t * 0.22) * 3.5
                let bobX2: Double = cos(t * 0.13) * 1.5
                let ambientDriftX = CGFloat(bobX1 + bobX2)
                let ambientDriftY = CGFloat(cos(t * 0.18) * 3.0 + sin(t * 0.27) * 1.2)

                let mouseParallaxX = CGFloat(mouseState.normX) * 3.5
                let mouseParallaxY = CGFloat(mouseState.normY) * 3.5
                let driftX = ambientDriftX * CGFloat(1.0 - inf * 0.6) + mouseParallaxX * CGFloat(inf)
                let driftY = ambientDriftY * CGFloat(1.0 - inf * 0.6) + mouseParallaxY * CGFloat(inf)

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
