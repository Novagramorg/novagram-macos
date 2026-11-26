import Cocoa
import TGUIKit
import LabSupport

public final class NodeHarness: HarnessBase {
    let scene: ChatLayerSceneView
    let group: ChatLayerNode
    let node: ChatLayerControlNode

    public override init(config: HarnessConfig) {
        LabPointer.install()
        scene = ChatLayerSceneView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        group = ChatLayerNode(id: "group")
        node = ChatLayerControlNode(id: "control")
        super.init(config: config)
        container.addSubview(scene)
        group.frame = NSRect(x: 20, y: 20, width: 200, height: 100)
        node.frame = NSRect(x: 30, y: 30, width: 100, height: 40)
        try! group.setChildren([node])
        try! scene.root.setChildren([group])
        scene.layout()
        node.sendRightMouseAnyway = config.sendRightMouseAnyway
        node.scaleOnClick = config.scaleOnClick
        node.scaleDownOnClick = config.scaleDownOnClick
        node.userInteractionEnabled = config.userInteractionEnabled
        node.isEnabled = config.isEnabled
        for event in config.events {
            node.set(handler: { [weak self] _ in self?.append("event:\(event)") }, for: event)
        }
        for state in config.states {
            node.set(handler: { [weak self] node in self?.append("state:\(state) now=\(node.controlState)") }, for: state)
        }
        if config.hasContextMenu {
            node.contextMenu = { [weak self] in self?.makeMenu() }
        }
    }

    public override var pressLayer: CALayer { node.layer }

    public override func dispatch(_ kind: HarnessEvent, _ event: NSEvent) {
        switch kind {
        case .moved: scene.mouseMoved(with: event)
        case .down: scene.mouseDown(with: event)
        case .dragged: scene.mouseDragged(with: event)
        case .up: scene.mouseUp(with: event)
        case .rightDown: scene.rightMouseDown(with: event)
        case .rightUp: scene.rightMouseUp(with: event)
        case .exitWindow: scene.mouseExited(with: event)
        }
    }

    public var sceneView: NSView { scene }
    public var nodeFrame: NSRect {
        get { node.frame }
        set { node.frame = newValue }
    }
    public var groupFrame: NSRect {
        get { group.frame }
        set { group.frame = newValue }
    }
    public var toolTip: String? {
        get { node.toolTip }
        set { node.toolTip = newValue }
    }
    public func removeNodeFromScene() {
        try! group.setChildren([])
    }
    public func readdNodeToScene() {
        try! group.setChildren([node])
    }
}
