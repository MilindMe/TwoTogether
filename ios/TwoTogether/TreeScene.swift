import SceneKit
#if canImport(HabitCore)
import HabitCore
#endif
#if os(iOS)
import UIKit
typealias SceneColor = UIColor
#else
import AppKit
typealias SceneColor = NSColor
#endif

/// What a habit's tree looks like. The same habit always grows the same shape: its layout is seeded by the habit id.
struct TreeSpec: Equatable {
    var id: String
    var color: String
    /// `Growth.level`: whole stages plus progress through the current one, 0…6.
    var level: Double
    var vitality: Double
    var stage: Stage { Stage(rawValue: min(Stage.ancient.rawValue, Int(level))) ?? .seed }
    /// Changes that need a new model. Anything else is an animated resize.
    var shape: [AnyHashable] { [id, color, stage, Int((vitality * 10).rounded())] }
}
extension TreeSpec {
    init(habit: Habit, growth: Growth) {
        self.init(id: habit.id, color: habit.color, level: growth.level, vitality: growth.vitality)
    }
}

/// A transparent scene holding one tree on a mound of soil, framed so the ground sits near the bottom edge.
/// The tree casts its shadow onto whatever is drawn behind the view, so it appears to grow out of the card.
final class TreeScene {
    let scene = SCNScene()
    private let holder = SCNNode()
    private var tree = SCNNode()
    private(set) var spec: TreeSpec?
    /// World units visible from bottom to top of the view. An ancient tree fills about 90% of it.
    static let viewHeight: Float = 3.1
    /// Where the ground sits, as a fraction of the view height from the bottom.
    static let ground: Float = 0.08
    /// Width over height of the view; wide trees are shrunk to fit it.
    var aspect: Float = 1 {
        didSet { if oldValue != aspect, let spec { tree.simdScale = fitted(spec) } }
    }
    var swaying = true { didSet { if oldValue != swaying { sway() } } }

    init() {
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = Double(Self.viewHeight / 2)
        camera.zNear = 0.1; camera.zFar = 40
        let tilt: Float = 0.16
        // Put the world origin `ground` of the way up the view, whatever the tilt.
        let target = camera.orthographicScale.f * (1 - 2 * Self.ground) / cos(tilt)
        let eye = SCNNode(); eye.camera = camera
        eye.simdPosition = [0, target + 12 * sin(tilt), 12 * cos(tilt)]
        eye.simdEulerAngles = [-tilt, 0, 0]
        scene.rootNode.addChildNode(eye)

        let ambient = SCNNode(); ambient.light = SCNLight()
        ambient.light!.type = .ambient; ambient.light!.color = SceneColor(white: 0.58, alpha: 1)
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode(); sun.light = SCNLight()
        sun.light!.type = .directional; sun.light!.color = SceneColor(red: 1, green: 0.96, blue: 0.88, alpha: 1)
        sun.light!.intensity = 900
        sun.light!.castsShadow = true; sun.light!.shadowMode = .deferred
        sun.light!.shadowColor = SceneColor(white: 0, alpha: 0.22)
        sun.light!.shadowRadius = 6; sun.light!.shadowSampleCount = 8
        sun.light!.orthographicScale = 4; sun.light!.shadowMapSize = CGSize(width: 1024, height: 1024)
        sun.simdEulerAngles = [-1.0, -0.6, 0]
        scene.rootNode.addChildNode(sun)

        // Invisible floor that only receives the shadow.
        let catcher = SCNNode(geometry: SCNPlane(width: 12, height: 12))
        catcher.geometry!.firstMaterial!.colorBufferWriteMask = []
        catcher.simdEulerAngles = [-.pi / 2, 0, 0]
        catcher.castsShadow = false
        scene.rootNode.addChildNode(catcher)

        scene.rootNode.addChildNode(Self.mound())
        scene.rootNode.addChildNode(holder)
    }

    /// Shows `spec`. A new stage rebuilds the tree; growing into a higher stage plays a burst of leaves.
    func apply(_ next: TreeSpec, animated: Bool) {
        defer { spec = next }
        guard let old = spec, old.shape == next.shape else {
            tree.removeFromParentNode()
            tree = TreeBuilder(next).build()
            holder.addChildNode(tree)
            let grew = spec.map { next.stage > $0.stage } ?? false
            if animated && grew {
                tree.simdScale = fitted(next) * 0.55
                SCNTransaction.begin(); SCNTransaction.animationDuration = 0.9
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.5, 0.64, 1)
                tree.simdScale = fitted(next)
                SCNTransaction.commit()
                burst(next)
            } else { tree.simdScale = fitted(next) }
            sway()
            return
        }
        guard old.level != next.level else { return }
        SCNTransaction.begin(); SCNTransaction.animationDuration = animated ? 0.6 : 0
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.4, 0.64, 1)
        tree.simdScale = fitted(next)
        SCNTransaction.commit()
    }

    /// Turns the tree about its trunk, for dragging it around in the detail view.
    func turn(by radians: Float) { holder.simdEulerAngles.y += radians }

    /// Height grows steadily with level; the model is scaled to it and kept inside the view's width.
    static func height(_ level: Double) -> Float { 0.3 + 0.42 * Float(level) }
    private func fitted(_ spec: TreeSpec) -> SIMD3<Float> {
        if spec.stage == .seed { return SIMD3(repeating: 1 + 0.5 * Float(spec.level)) }
        let (natural, halfWidth) = Self.extent(tree)
        let room = Self.viewHeight / 2 * aspect * 0.94
        return SIMD3(repeating: min(Self.height(spec.level) / natural, room / halfWidth))
    }
    /// Height and on-screen half width of a model in its own space. SceneKit's bounding boxes of rotated
    /// children are far too loose for framing, so this measures each part's bounding sphere instead.
    static func extent(_ tree: SCNNode) -> (height: Float, halfWidth: Float) {
        var top: Float = 0.01, half: Float = 0.01
        tree.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            let (center, radius) = geometry.boundingSphere
            let p = tree.simdConvertPosition(SIMD3(center), from: node)
            let r = radius.f * node.simdScale.max()
            top = max(top, p.y + r); half = max(half, abs(p.x) + r)
        }
        return (top, half)
    }
    private func sway() {
        tree.removeAction(forKey: "sway")
        guard swaying, spec?.stage != .seed else { tree.simdEulerAngles = .zero; return }
        let a = SCNAction.rotateTo(x: 0, y: 0, z: 0.025, duration: 2.4, usesShortestUnitArc: true)
        let b = SCNAction.rotateTo(x: 0, y: 0, z: -0.025, duration: 2.4, usesShortestUnitArc: true)
        a.timingMode = .easeInEaseOut; b.timingMode = .easeInEaseOut
        tree.runAction(.repeatForever(.sequence([a, b])), forKey: "sway")
    }
    private func burst(_ spec: TreeSpec) {
        let leaves = SCNParticleSystem()
        leaves.birthRate = 400; leaves.emissionDuration = 0.12; leaves.loops = false
        leaves.particleLifeSpan = 1.1; leaves.particleLifeSpanVariation = 0.4
        leaves.particleSize = 0.05; leaves.particleSizeVariation = 0.03
        leaves.particleVelocity = 2.2; leaves.particleVelocityVariation = 1; leaves.spreadingAngle = 70
        leaves.acceleration = SCNVector3(0, -3, 0)
        leaves.particleColor = Foliage.color(spec.color); leaves.particleColorVariation = SCNVector4(0.04, 0.1, 0.15, 0)
        leaves.particleAngularVelocity = 360; leaves.particleAngularVelocityVariation = 360
        leaves.emitterShape = SCNSphere(radius: 0.3)
        let at = SCNNode(); at.simdPosition = [0, Self.height(spec.level) * 0.7, 0]
        scene.rootNode.addChildNode(at)
        at.addParticleSystem(leaves)
        at.runAction(.sequence([.wait(duration: 2.5), .removeFromParentNode()]))
    }
    private static func mound() -> SCNNode {
        let soil = SCNSphere(radius: 0.55); soil.isGeodesic = true; soil.segmentCount = 3
        soil.materials = [Foliage.material(Foliage.soil)]
        let node = SCNNode()
        let dome = SCNNode(geometry: soil); dome.simdScale = [1, 0.18, 0.85]
        node.addChildNode(dome)
        var rng = SplitMix("pebbles")
        for i in 0..<5 {
            let pebble = SCNSphere(radius: CGFloat(rng.range(0.03, 0.06))); pebble.isGeodesic = true; pebble.segmentCount = 1
            pebble.materials = [Foliage.material(SceneColor(white: CGFloat(rng.range(0.55, 0.75)), alpha: 1))]
            let p = SCNNode(geometry: pebble)
            let angle = Float(i) * 1.3 + rng.range(0, 0.6), r = rng.range(0.3, 0.46)
            p.simdPosition = [cos(angle) * r, 0.05, sin(angle) * r * 0.8]
            node.addChildNode(p)
        }
        return node
    }
}

/// Grows one tree model. Seeds and sprouts are modelled by hand; saplings and older trees branch recursively.
final class TreeBuilder {
    private var rng: SplitMix
    private let spec: TreeSpec
    private let bark = Foliage.material(Foliage.bark)
    private var clusters: [SCNNode] = []
    init(_ spec: TreeSpec) { self.spec = spec; rng = SplitMix(spec.id) }

    func build() -> SCNNode {
        let tree = SCNNode()
        let stage = spec.stage
        switch stage {
        case .seed: seed(tree)
        case .sprout: sprout(tree)
        default:
            let depth = [0, 0, 2, 3, 3, 4, 4][stage.rawValue]
            let lean = SCNNode(); lean.simdEulerAngles = [rng.range(-0.06, 0.06), 0, rng.range(-0.06, 0.06)]
            tree.addChildNode(lean)
            limb(lean, depth: 0, maxDepth: depth, length: 1, radius: 0.08 + 0.012 * Float(stage.rawValue), bushy: stage >= .mature)
            thin()
        }
        return tree
    }

    private func limb(_ parent: SCNNode, depth: Int, maxDepth: Int, length: Float, radius: Float, bushy: Bool) {
        let cone = SCNCone(topRadius: CGFloat(radius * 0.68), bottomRadius: CGFloat(radius * (depth == 0 ? 1.35 : 1)), height: CGFloat(length))
        cone.radialSegmentCount = 7; cone.heightSegmentCount = 1; cone.materials = [bark]
        let segment = SCNNode(geometry: cone); segment.simdPosition = [0, length / 2, 0]
        parent.addChildNode(segment)
        let tip = SCNNode(); tip.simdPosition = [0, length, 0]
        parent.addChildNode(tip)
        if depth == maxDepth { cluster(tip, radius: length * 0.85); return }
        if depth == maxDepth - 1 { cluster(tip, radius: length * 0.55) }
        let count = depth == 0 || (bushy && rng.unit() < 0.6) ? 3 : 2
        let turn = rng.range(0, 2 * .pi)
        // Deeper branches fork more gently, so the canopy stays upright rather than drooping.
        let fork: ClosedRange<Float> = depth == 0 ? 0.42...0.68 : 0.3...0.52
        for i in 0..<count {
            let yaw = SCNNode(); yaw.simdEulerAngles = [0, turn + Float(i) * 2 * .pi / Float(count) + rng.range(-0.35, 0.35), 0]
            let pitch = SCNNode(); pitch.simdEulerAngles = [rng.range(fork.lowerBound, fork.upperBound), 0, 0]
            tip.addChildNode(yaw); yaw.addChildNode(pitch)
            limb(pitch, depth: depth + 1, maxDepth: maxDepth, length: length * rng.range(0.64, 0.78), radius: radius * 0.62, bushy: bushy)
        }
        // A leader keeps the trunk going up through the first forks.
        if depth < maxDepth - 2 || depth == 0 {
            let lead = SCNNode(); lead.simdEulerAngles = [rng.range(-0.15, 0.15), 0, rng.range(-0.15, 0.15)]
            tip.addChildNode(lead)
            limb(lead, depth: depth + 1, maxDepth: maxDepth, length: length * rng.range(0.7, 0.82), radius: radius * 0.74, bushy: bushy)
        }
    }

    private func cluster(_ at: SCNNode, radius: Float) {
        let ball = SCNSphere(radius: CGFloat(radius)); ball.isGeodesic = true; ball.segmentCount = 2
        ball.materials = [Foliage.material(Foliage.leaf(spec.color, vitality: spec.vitality, shade: rng.range(-0.08, 0.08)))]
        let node = SCNNode(geometry: ball)
        node.simdPosition = [rng.range(-0.15, 0.15) * radius, radius * 0.35, rng.range(-0.15, 0.15) * radius]
        node.simdScale = [1, rng.range(0.72, 0.9), 1]
        node.simdEulerAngles = [rng.range(0, 1), rng.range(0, 6.3), rng.range(0, 1)]
        // Clusters hang in world space regardless of how the branch is turned.
        at.addChildNode(node)
        clusters.append(node)
    }

    /// A dry tree drops foliage. Keep at least the first cluster so it never looks dead.
    private func thin() {
        let keep = 0.35 + 0.65 * Float(spec.vitality)
        for node in clusters.dropFirst() where rng.unit() > keep { node.removeFromParentNode() }
    }

    private func seed(_ tree: SCNNode) {
        let shell = SCNSphere(radius: 0.11); shell.isGeodesic = true; shell.segmentCount = 2
        shell.materials = [Foliage.material(SceneColor(red: 0.55, green: 0.36, blue: 0.2, alpha: 1))]
        let seed = SCNNode(geometry: shell); seed.simdScale = [0.8, 1.15, 0.8]
        seed.simdPosition = [0, 0.1, 0]; seed.simdEulerAngles = [0.2, 0, 0.35]
        tree.addChildNode(seed)
        // The shoot appears a third of the way to a sprout, and its first leaf two thirds of the way.
        let progress = spec.level
        if progress >= 1.0 / 3 {
            let shoot = SCNCone(topRadius: 0.008, bottomRadius: 0.018, height: 0.16)
            shoot.materials = [Foliage.material(Foliage.stem)]
            let node = SCNNode(geometry: shoot); node.simdPosition = [0.02, 0.24, 0]; node.simdEulerAngles = [0, 0, -0.25]
            tree.addChildNode(node)
            if progress >= 2.0 / 3 { leaf(tree, at: [0.04, 0.31, 0], yaw: 0, size: 0.07) }
        }
    }

    private func sprout(_ tree: SCNNode) {
        let stem = SCNCone(topRadius: 0.012, bottomRadius: 0.028, height: 0.55)
        stem.materials = [Foliage.material(Foliage.stem)]
        let node = SCNNode(geometry: stem); node.simdPosition = [0, 0.275, 0]
        tree.addChildNode(node)
        let pairs = 1 + Int((spec.level - 1) * 3)
        for i in 0..<pairs {
            let y = 0.55 - Float(i) * 0.14, size = 0.12 - Float(i) * 0.015
            leaf(tree, at: [0, y, 0], yaw: Float(i) * 1.6, size: size)
            leaf(tree, at: [0, y, 0], yaw: Float(i) * 1.6 + .pi, size: size)
        }
    }
    private func leaf(_ tree: SCNNode, at position: SIMD3<Float>, yaw: Float, size: Float) {
        let blade = SCNSphere(radius: CGFloat(size)); blade.isGeodesic = true; blade.segmentCount = 1
        blade.materials = [Foliage.material(Foliage.leaf(spec.color, vitality: spec.vitality, shade: 0))]
        let pivot = SCNNode(); pivot.simdPosition = position; pivot.simdEulerAngles = [0, yaw, 0.5]
        let node = SCNNode(geometry: blade); node.simdPosition = [size * 0.9, 0, 0]; node.simdScale = [1, 0.28, 0.7]
        pivot.addChildNode(node); tree.addChildNode(pivot)
        clusters.append(node)
    }
}

/// Foliage, bark and soil colours. Each habit colour picks a tree species' palette.
enum Foliage {
    static let bark = SceneColor(red: 0.46, green: 0.32, blue: 0.23, alpha: 1)
    static let soil = SceneColor(red: 0.42, green: 0.3, blue: 0.21, alpha: 1)
    static let stem = SceneColor(red: 0.42, green: 0.62, blue: 0.3, alpha: 1)
    private static let dry: SIMD3<Float> = [0.64, 0.53, 0.33]
    private static let tones: [String: SIMD3<Float>] = [
        "red": [0.86, 0.27, 0.25], "orange": [0.95, 0.55, 0.2], "yellow": [0.96, 0.8, 0.26], "green": [0.38, 0.71, 0.32],
        "mint": [0.42, 0.83, 0.63], "teal": [0.2, 0.63, 0.63], "blue": [0.35, 0.56, 0.88], "indigo": [0.42, 0.41, 0.82],
        "purple": [0.65, 0.43, 0.85], "pink": [0.97, 0.6, 0.75],
    ]
    static func color(_ name: String) -> SceneColor { rgb(tones[name] ?? tones["green"]!) }
    /// Below full vitality leaves fade toward straw; `shade` varies each cluster a little.
    static func leaf(_ name: String, vitality: Double, shade: Float) -> SceneColor {
        let dryness = Float(min(1, max(0, (0.75 - vitality) / 0.75))) * 0.85
        let base = tones[name] ?? tones["green"]!
        return rgb((base + (dry - base) * dryness) * (1 + shade))
    }
    private static func rgb(_ c: SIMD3<Float>) -> SceneColor {
        SceneColor(red: CGFloat(min(1, c.x)), green: CGFloat(min(1, c.y)), blue: CGFloat(min(1, c.z)), alpha: 1)
    }
    /// Lambert with face normals, for a faceted low-poly look.
    static func material(_ color: SceneColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color; m.lightingModel = .lambert
        m.shaderModifiers = [.surface: "_surface.normal = normalize(cross(dfdy(_surface.position), dfdx(_surface.position)));"]
        return m
    }
}

/// Small deterministic generator, so a habit's tree keeps its shape across launches and devices.
struct SplitMix {
    private var state: UInt64
    init(_ text: String) {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        state = hash
    }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }
    mutating func range(_ a: Float, _ b: Float) -> Float { a + (b - a) * unit() }
}

private extension BinaryFloatingPoint { var f: Float { Float(self) } }
