import SwiftUI
import SceneKit
#if canImport(HabitCore)
import HabitCore
#endif

/// A live 3D tree on a transparent background. Place it so its bottom edge overlaps a card:
/// the mound sits 8% up from the bottom and the shadow falls on whatever is behind.
struct TreeView: UIViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let spec: TreeSpec
    /// Lets a drag turn the tree.
    var interactive = false

    final class Coordinator: NSObject {
        let tree = TreeScene()
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            let dx = Float(gesture.translation(in: gesture.view).x)
            gesture.setTranslation(.zero, in: gesture.view)
            tree.turn(by: dx * 0.012)
        }
    }
    final class Canvas: SCNView {
        var onLayout: ((CGSize) -> Void)?
        override func layoutSubviews() { super.layoutSubviews(); onLayout?(bounds.size) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> SCNView {
        let view = Canvas(frame: .zero)
        let tree = context.coordinator.tree
        view.scene = tree.scene
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.onLayout = { size in if size.height > 0 { tree.aspect = Float(size.width / size.height) } }
        if interactive {
            view.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan)))
        }
        tree.apply(spec, animated: false)
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        let tree = context.coordinator.tree
        tree.swaying = !reduceMotion
        // Without sway there is nothing to animate between changes, so stop the render loop.
        view.isPlaying = !reduceMotion
        tree.apply(spec, animated: !reduceMotion)
    }
}
