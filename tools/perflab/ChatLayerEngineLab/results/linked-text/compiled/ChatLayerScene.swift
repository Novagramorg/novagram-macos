import Cocoa
import TGUIKit

enum ChatLayerTreeError: Error, Equatable {
    case duplicateIdentifier
    case alreadyParented
    case cycle
}

struct ChatLayerPointerEvent {
    enum Kind {
        case entered, exited, moved, down, dragged, up, cancelled
    }
    let kind: Kind
    let location: NSPoint
    let sceneLocation: NSPoint
    let button: Int
    let clickCount: Int
    let modifiers: NSEvent.ModifierFlags
    let nativeEvent: NSEvent?
}

class ChatLayerNode {
    let id: AnyHashable
    let layer: SimpleLayer
    private(set) weak var parent: ChatLayerNode?
    fileprivate(set) weak var scene: ChatLayerSceneView?
    private(set) var children: [ChatLayerNode] = []
    fileprivate var orderedChildren: [ChatLayerNode] = []
    fileprivate var accessibilityElement: ChatLayerAccessibilityElement?

    var acceptsPointerEvents = false {
        didSet {
            if acceptsPointerEvents != oldValue { scene?.invalidateHitIndex(); scene?.validateInput() }
        }
    }
    var isEnabled = true { didSet { scene?.validateInput() } }
    var acceptsKeyboardFocus = false { didSet { scene?.validateInput() } }
    var cursor: NSCursor?
    var hitRegion: ((NSPoint) -> Bool)? { didSet { scene?.invalidateHitIndex() } }
    var onPointer: ((ChatLayerPointerEvent) -> Bool)?
    var onCommand: ((Selector) -> Bool)?
    var onKeyDown: ((NSEvent) -> Bool)?
    var onFocusChanged: ((Bool) -> Void)?
    var onWindowKeyChanged: ((Bool) -> Void)?
    var menu: ((ChatLayerPointerEvent) -> NSMenu?)?
    var onAccessibilityPress: (() -> Bool)?
    var accessibilityRole: NSAccessibility.Role?
    var accessibilityLabel: String?
    var accessibilityValue: String?

    var frame: NSRect {
        get { layer.frame }
        set {
            let frame = NSRect(origin: newValue.origin, size: NSSize(width: max(0, newValue.width), height: max(0, newValue.height)))
            guard layer.frame != frame else { return }
            layer.frame = frame
            scene?.invalidateHitIndex()
            scene?.needsLayout = true
        }
    }
    var transform: CATransform3D {
        get { layer.transform }
        set { layer.transform = newValue; scene?.invalidateHitIndex(); scene?.needsLayout = true }
    }
    var sublayerTransform: CATransform3D {
        get { layer.sublayerTransform }
        set { layer.sublayerTransform = newValue; scene?.invalidateHitIndex(); scene?.needsLayout = true }
    }
    var isHidden: Bool {
        get { layer.isHidden }
        set { layer.isHidden = newValue; scene?.validateInput() }
    }
    var opacity: Float {
        get { layer.opacity }
        set { layer.opacity = newValue; scene?.validateInput() }
    }
    var clipsChildren: Bool {
        get { layer.masksToBounds }
        set {
            guard layer.masksToBounds != newValue else { return }
            layer.masksToBounds = newValue
            scene?.needsLayout = true
        }
    }
    var zIndex: Int = 0 {
        didSet {
            layer.zPosition = CGFloat(zIndex)
            parent?.sortChildren()
            scene?.needsLayout = true
        }
    }

    init(id: AnyHashable, layer: SimpleLayer = SimpleLayer()) {
        self.id = id
        self.layer = layer
        layer.anchorPoint = .zero
        layer.edgeAntialiasingMask = []
    }

    func setChildren(_ children: [ChatLayerNode]) throws {
        if self.children.count == children.count && zip(self.children, children).allSatisfy({ $0 === $1 }) { return }
        for child in children {
            if let parent = child.parent, parent !== self { throw ChatLayerTreeError.alreadyParented }
            var ancestor: ChatLayerNode? = self
            while let node = ancestor {
                if node === child { throw ChatLayerTreeError.cycle }
                ancestor = node.parent
            }
        }
        var root = self
        while let parent = root.parent { root = parent }
        var identifiers = Set<AnyHashable>()
        var objects = Set<ObjectIdentifier>()
        func validate(_ node: ChatLayerNode) throws {
            guard objects.insert(ObjectIdentifier(node)).inserted else { throw ChatLayerTreeError.cycle }
            guard identifiers.insert(node.id).inserted else { throw ChatLayerTreeError.duplicateIdentifier }
            for child in node === self ? children : node.children { try validate(child) }
        }
        try validate(root)
        let retained = Set(children.map(ObjectIdentifier.init))
        for child in self.children where !retained.contains(ObjectIdentifier(child)) {
            child.parent = nil
            child.attach(to: nil)
            child.layer.removeFromSuperlayer()
        }
        let previousLayers = Set(self.children.map { ObjectIdentifier($0.layer) })
        let contentCount = (layer.sublayers ?? []).filter { !previousLayers.contains(ObjectIdentifier($0)) }.count
        self.children = children
        for (offset, child) in children.enumerated() {
            let index = contentCount + offset
            child.parent = self
            child.attach(to: scene)
            if (layer.sublayers?.count ?? 0) <= index || layer.sublayers?[index] !== child.layer {
                layer.insertSublayer(child.layer, at: UInt32(index))
            }
        }
        sortChildren()
        scene?.treeDidChange()
    }

    fileprivate func sortChildren() {
        scene?.invalidateHitIndex()
        orderedChildren = children.enumerated().sorted {
            $0.element.zIndex == $1.element.zIndex ? $0.offset < $1.offset : $0.element.zIndex < $1.element.zIndex
        }.map(\.element)
    }

    func attach(to scene: ChatLayerSceneView?) {
        guard self.scene !== scene else { return }
        self.scene = scene
        if let scene {
            updateOwnScale(scene.backingScaleFactor)
            onWindowKeyChanged?(scene.window?.isKeyWindow ?? false)
        }
        for child in children { child.attach(to: scene) }
    }

    func updateOwnScale(_ scale: CGFloat) {
        if layer.contentsScale != scale {
            layer.contentsScale = scale
            layer.setNeedsDisplay()
        }
    }

    fileprivate func updateScale(_ scale: CGFloat) {
        updateOwnScale(scale)
        for child in children { child.updateScale(scale) }
    }

    var isVisible: Bool {
        return !isHidden && opacity > 0 && (parent?.isVisible ?? true)
    }

    var isEffectivelyEnabled: Bool { isEnabled && (parent?.isEffectivelyEnabled ?? true) }

    fileprivate func contains(_ point: NSPoint) -> Bool {
        return hitRegion?(point) ?? layer.bounds.contains(point)
    }

    fileprivate func allowsHit(at point: NSPoint, from root: CALayer) -> Bool {
        guard isVisible, contains(layer.convert(point, from: root)) else { return false }
        var current: ChatLayerNode? = self
        while let ancestor = current {
            if ancestor.clipsChildren {
                let local = ancestor.layer.convert(point, from: root)
                guard ancestor.layer.bounds.contains(local) else { return false }
                let radius = ancestor.layer.cornerRadius
                if radius > 0 && !CGPath(roundedRect: ancestor.layer.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil).contains(local) { return false }
            }
            current = ancestor.parent
        }
        return true
    }

    fileprivate func accessibilityHit(at point: NSPoint, from root: CALayer) -> ChatLayerAccessibilityElement? {
        guard isVisible else { return nil }
        let local = layer.convert(point, from: root)
        if clipsChildren && !layer.bounds.contains(local) { return nil }
        for child in orderedChildren.reversed() {
            if let result = child.accessibilityHit(at: point, from: root) { return result }
        }
        guard accessibilityRole != nil, layer.bounds.contains(local) else { return nil }
        if accessibilityElement == nil { accessibilityElement = ChatLayerAccessibilityElement(node: self) }
        return accessibilityElement
    }

    fileprivate func accessibleChildren() -> [ChatLayerAccessibilityElement] {
        guard isVisible else { return [] }
        return orderedChildren.flatMap { node -> [ChatLayerAccessibilityElement] in
            guard node.isVisible else { return [] }
            if node.accessibilityRole != nil {
                if node.accessibilityElement == nil { node.accessibilityElement = ChatLayerAccessibilityElement(node: node) }
                return [node.accessibilityElement!]
            }
            return node.accessibleChildren()
        }
    }
}

class ChatLayerSceneView: View {
    let root: ChatLayerNode
    var selectableTextNodeIds: [AnyHashable] = [] {
        willSet { if selectableTextNodeIds != newValue { clearBubbleSelection() } }
    }
    private var nodes: [AnyHashable: ChatLayerNode] = [:]
    private var hitIndex: [(node: ChatLayerNode, frame: NSRect)] = []
    private var hitIndexIsValid = false
    private var captures: [Int: ChatLayerNode] = [:]
    private var blockedButtons = Set<Int>()
    private var hovered: [ChatLayerNode] = []
    private var hoverGeneration = 0
    private var inputGeneration = 0
    private var lastPointer: NSPoint?
    private var pointerArea: NSTrackingArea?
    private var toolTipNodes: [ChatLayerTextNode]?
    private(set) var geometryVersion: UInt64 = 0
    private(set) weak var focusedNode: ChatLayerNode?

    override var isHidden: Bool {
        didSet { if isHidden { cancelInput() } }
    }

    required convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, ownedRoot: ChatLayerNode(id: UUID()))
    }

    init(frame frameRect: NSRect, ownedRoot: ChatLayerNode) {
        precondition(ownedRoot.parent == nil && ownedRoot.scene == nil)
        root = ownedRoot
        super.init(frame: frameRect)
        layer?.addSublayer(root.layer)
        root.attach(to: self)
        treeDidChange()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func node(id: AnyHashable) -> ChatLayerNode? { nodes[id] }

    override func layout() {
        super.layout()
        root.layer.frame = bounds
        invalidateHitIndex()
        toolTipNodes?.forEach { $0.synchronizeLinkToolTips(force: false) }
        if let point = lastPointer {
            updateHover(at: point)
            if let node = hovered.last as? ChatLayerTextNode {
                node.refreshLinkHover(at: node.layer.convert(point, from: root.layer))
            }
        }
    }

    func registerToolTipNode(_ node: ChatLayerTextNode) {
        if toolTipNodes?.contains(where: { $0 === node }) != true {
            if toolTipNodes == nil { toolTipNodes = [] }
            toolTipNodes?.append(node)
        }
    }

    func unregisterToolTipNode(_ node: ChatLayerTextNode) {
        toolTipNodes?.removeAll(where: { $0 === node })
        if toolTipNodes?.isEmpty == true { toolTipNodes = nil }
    }

    override func removeAllToolTips() {
        super.removeAllToolTips()
        toolTipNodes?.forEach { $0.didRemoveLinkToolTips() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        root.updateScale(backingScaleFactor)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if window !== newWindow {
            cancelInput()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
            if let newWindow {
                NotificationCenter.default.addObserver(self, selector: #selector(windowKeyChanged), name: NSWindow.didResignKeyNotification, object: newWindow)
                NotificationCenter.default.addObserver(self, selector: #selector(windowKeyChanged), name: NSWindow.didBecomeKeyNotification, object: newWindow)
            }
        }
    }

    @objc private func windowKeyChanged() {
        let isKey = window?.isKeyWindow ?? false
        if !isKey { cancelInput(preservingFocus: true) }
        for node in nodes.values { node.onWindowKeyChanged?(isKey) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        root.updateScale(backingScaleFactor)
        windowKeyChanged()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea { removeTrackingArea(pointerArea) }
        let area = NSTrackingArea(rect: .zero, options: [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate], owner: self)
        addTrackingArea(area)
        pointerArea = area
    }

    fileprivate func invalidateHitIndex() {
        geometryVersion &+= 1
        if hitIndexIsValid { hitIndex.removeAll(keepingCapacity: true) }
        hitIndexIsValid = false
    }

    fileprivate func treeDidChange() {
        invalidateHitIndex()
        var updated: [AnyHashable: ChatLayerNode] = [:]
        func visit(_ node: ChatLayerNode) {
            updated[node.id] = node
            for child in node.children { visit(child) }
        }
        visit(root)
        nodes = updated
        validateInput()
        needsLayout = true
    }

    fileprivate func validateInput() {
        for (button, node) in captures where node.scene !== self || !node.isVisible || !node.isEffectivelyEnabled || isHiddenOrHasHiddenAncestor {
            guard captures[button] === node else { continue }
            captures.removeValue(forKey: button)
            blockedButtons.insert(button)
            _ = node.onPointer?(event(.cancelled, node: nil, point: lastPointer ?? .zero, button: button))
        }
        if let node = focusedNode, node.scene !== self || !node.isVisible || !node.isEffectivelyEnabled || !node.acceptsKeyboardFocus {
            focus(nil)
        }
        if let point = lastPointer { updateHover(at: point) }
    }

    var hasActiveInput: Bool { !captures.isEmpty || focusedNode != nil || lastPointer != nil || !hovered.isEmpty }

    func cancelInput(preservingFocus: Bool = false) {
        let previous = captures
        captures.removeAll()
        blockedButtons.formUnion(previous.keys)
        if !preservingFocus { focus(nil) }
        lastPointer = nil
        for (button, node) in previous {
            _ = node.onPointer?(event(.cancelled, node: nil, point: .zero, button: button))
        }
        updateHover(at: nil)
    }

    func focus(_ node: ChatLayerNode?) {
        guard focusedNode !== node else { return }
        if let node {
            guard node.scene === self, node.isVisible, node.isEffectivelyEnabled, node.acceptsKeyboardFocus else { return }
        }
        let previous = focusedNode
        focusedNode = node
        previous?.onFocusChanged?(false)
        if focusedNode === node { node?.onFocusChanged?(true) }
    }

    override func resignFirstResponder() -> Bool {
        focus(nil)
        return super.resignFirstResponder()
    }

    func hitNode(at point: NSPoint) -> ChatLayerNode? {
        guard !isHiddenOrHasHiddenAncestor, bounds.contains(point) else { return nil }
        if !hitIndexIsValid {
            hitIndex.removeAll(keepingCapacity: true)
            func visit(_ node: ChatLayerNode) {
                if node.acceptsPointerEvents {
                    hitIndex.append((node, node.layer.convert(node.layer.bounds, to: root.layer)))
                }
                for child in node.orderedChildren { visit(child) }
            }
            visit(root)
            hitIndexIsValid = true
        }
        for entry in hitIndex.reversed() where entry.node.hitRegion != nil || entry.frame.contains(point) {
            if entry.node.allowsHit(at: point, from: root.layer), entry.node.scene === self, entry.node.acceptsPointerEvents { return entry.node }
        }
        return nil
    }

    private func event(_ kind: ChatLayerPointerEvent.Kind, node: ChatLayerNode?, point: NSPoint, button: Int = 0, native: NSEvent? = nil) -> ChatLayerPointerEvent {
        var clickCount = 1
        if let native {
            switch native.type {
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged:
                clickCount = native.clickCount
            default:
                break
            }
        }
        return ChatLayerPointerEvent(kind: kind, location: node?.layer.convert(point, from: root.layer) ?? .zero, sceneLocation: point, button: button, clickCount: clickCount, modifiers: native?.modifierFlags ?? [], nativeEvent: native)
    }

    private func path(to node: ChatLayerNode?) -> [ChatLayerNode] {
        var result: [ChatLayerNode] = []
        var current = node
        while let node = current {
            result.append(node)
            current = node.parent
        }
        return result.reversed()
    }

    func updateHover(at point: NSPoint?) {
        hoverGeneration += 1
        let generation = hoverGeneration
        let target = point.flatMap(hitNode)
        let next = path(to: target?.isEffectivelyEnabled == true ? target : nil)
        let previous = hovered
        hovered = next
        let common = zip(previous, next).prefix { $0 === $1 }.count
        for node in previous.dropFirst(common).reversed() {
            guard hoverGeneration == generation else { return }
            _ = node.onPointer?(event(.exited, node: node.scene === self ? node : nil, point: point ?? .zero))
        }
        for node in next.dropFirst(common) {
            guard hoverGeneration == generation else { return }
            _ = node.onPointer?(event(.entered, node: node, point: point ?? .zero))
        }
        guard hoverGeneration == generation else { return }
        (next.reversed().compactMap(\.cursor).first ?? .arrow).set()
    }

    @discardableResult func handlePointer(_ kind: ChatLayerPointerEvent.Kind, at point: NSPoint, button: Int = 0, native: NSEvent? = nil) -> Bool {
        inputGeneration += 1
        let generation = inputGeneration
        if isHiddenOrHasHiddenAncestor { cancelInput() }
        lastPointer = point
        updateHover(at: point)
        if kind == .up {
            if blockedButtons.remove(button) != nil { return true }
            guard let target = captures.removeValue(forKey: button) else { return false }
            _ = target.onPointer?(event(kind, node: target, point: point, button: button, native: native))
            return true
        }
        if kind == .dragged {
            if blockedButtons.contains(button) { return true }
            guard let target = captures[button] else { return false }
            _ = target.onPointer?(event(kind, node: target, point: point, button: button, native: native))
            return true
        }
        if kind == .down {
            blockedButtons.remove(button)
            if let previous = captures.removeValue(forKey: button) {
                _ = previous.onPointer?(event(.cancelled, node: previous, point: point, button: button, native: native))
                guard inputGeneration == generation else { return true }
            }
        }
        guard let target = hitNode(at: point) else { return false }
        if !target.isEffectivelyEnabled {
            if kind == .down { blockedButtons.insert(button) }
            return true
        }
        for node in path(to: target).reversed() where node.scene === self {
            if node.onPointer?(event(kind, node: node, point: point, button: button, native: native)) == true {
                if kind == .down && inputGeneration == generation {
                    if node.scene === self && node.isVisible && node.isEffectivelyEnabled {
                        captures[button] = node
                        if node.acceptsKeyboardFocus {
                            focus(node)
                            window?.makeFirstResponder(self)
                        }
                    } else {
                        blockedButtons.insert(button)
                        _ = node.onPointer?(event(.cancelled, node: nil, point: point, button: button, native: native))
                    }
                }
                return true
            }
        }
        return false
    }

    private var focusCandidates: [ChatLayerNode] {
        guard !isHiddenOrHasHiddenAncestor else { return [] }
        var candidates: [ChatLayerNode] = []
        func visit(_ node: ChatLayerNode) {
            guard node.isVisible, node.isEffectivelyEnabled else { return }
            if node.acceptsKeyboardFocus { candidates.append(node) }
            for child in node.orderedChildren { visit(child) }
        }
        visit(root)
        return candidates
    }

    @discardableResult func moveFocus(backward: Bool) -> Bool {
        let candidates = focusCandidates
        guard !candidates.isEmpty else { return false }
        let index = focusedNode.flatMap { current in candidates.firstIndex { $0 === current } }
        let next = index.map { $0 + (backward ? -1 : 1) } ?? (backward ? candidates.count - 1 : 0)
        guard candidates.indices.contains(next) else { return false }
        focus(candidates[next])
        window?.makeFirstResponder(self)
        return true
    }

    private var keyboardTarget: ChatLayerNode? {
        guard !isHiddenOrHasHiddenAncestor, let node = focusedNode, node.scene === self, node.isVisible, node.isEffectivelyEnabled else { return nil }
        return node
    }

    @objc func copy(_ sender: Any?) { _ = keyboardTarget?.onCommand?(#selector(copy(_:))) }
    @objc override func selectAll(_ sender: Any?) { _ = keyboardTarget?.onCommand?(#selector(selectAll(_:))) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .option, .control]) == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": if keyboardTarget?.onCommand?(#selector(copy(_:))) == true { return true }
            case "a": if keyboardTarget?.onCommand?(#selector(selectAll(_:))) == true { return true }
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for native: NSEvent) -> NSMenu? {
        let point = convert(native.locationInWindow, from: nil)
        guard let target = hitNode(at: point), target.isEffectivelyEnabled else { return super.menu(for: native) }
        for node in path(to: target).reversed() {
            if let menu = node.menu?(event(.down, node: node, point: point, button: 1, native: native)) { return menu }
        }
        return super.menu(for: native)
    }

    override var acceptsFirstResponder: Bool { !focusCandidates.isEmpty }
    override var canBecomeKeyView: Bool { acceptsFirstResponder }
    override func becomeFirstResponder() -> Bool {
        if focusedNode == nil { focus(focusCandidates.first) }
        return super.becomeFirstResponder()
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 48 {
            let backward = event.modifierFlags.contains(.shift)
            if moveFocus(backward: backward) { return }
            if backward { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
            return
        }
        if keyboardTarget?.onKeyDown?(event) != true { super.keyDown(with: event) }
    }
    override func mouseDown(with event: NSEvent) {
        if !handlePointer(.down, at: convert(event.locationInWindow, from: nil), native: event) { super.mouseDown(with: event) }
    }
    override func mouseDragged(with event: NSEvent) {
        if !handlePointer(.dragged, at: convert(event.locationInWindow, from: nil), native: event) { super.mouseDragged(with: event) }
    }
    override func mouseUp(with event: NSEvent) {
        if !handlePointer(.up, at: convert(event.locationInWindow, from: nil), native: event) { super.mouseUp(with: event) }
    }
    override func rightMouseDown(with event: NSEvent) {
        if !handlePointer(.down, at: convert(event.locationInWindow, from: nil), button: 1, native: event) { super.rightMouseDown(with: event) }
    }
    override func rightMouseDragged(with event: NSEvent) {
        if !handlePointer(.dragged, at: convert(event.locationInWindow, from: nil), button: 1, native: event) { super.rightMouseDragged(with: event) }
    }
    override func otherMouseDown(with event: NSEvent) {
        if !handlePointer(.down, at: convert(event.locationInWindow, from: nil), button: event.buttonNumber, native: event) { super.otherMouseDown(with: event) }
    }
    override func otherMouseDragged(with event: NSEvent) {
        if !handlePointer(.dragged, at: convert(event.locationInWindow, from: nil), button: event.buttonNumber, native: event) { super.otherMouseDragged(with: event) }
    }
    override func otherMouseUp(with event: NSEvent) {
        if !handlePointer(.up, at: convert(event.locationInWindow, from: nil), button: event.buttonNumber, native: event) { super.otherMouseUp(with: event) }
    }
    override func rightMouseUp(with event: NSEvent) {
        if !handlePointer(.up, at: convert(event.locationInWindow, from: nil), button: 1, native: event) { super.rightMouseUp(with: event) }
    }
    override func mouseMoved(with event: NSEvent) {
        _ = handlePointer(.moved, at: convert(event.locationInWindow, from: nil), native: event)
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { lastPointer = nil; updateHover(at: nil) }
    override func cursorUpdate(with event: NSEvent) { mouseMoved(with: event) }

    override func isAccessibilityElement() -> Bool {
        TGUIKitAccessibility.isEnabled && !isHiddenOrHasHiddenAncestor && !root.accessibleChildren().isEmpty
    }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityChildren() -> [Any]? {
        guard TGUIKitAccessibility.isEnabled, !isHiddenOrHasHiddenAncestor else { return nil }
        return root.accessibleChildren()
    }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        guard let window else { return super.accessibilityHitTest(point) }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        if TGUIKitAccessibility.isEnabled, !isHiddenOrHasHiddenAncestor, bounds.contains(local), let result = root.accessibilityHit(at: local, from: root.layer) { return result }
        return super.accessibilityHitTest(point)
    }
}

fileprivate final class ChatLayerAccessibilityElement: NSAccessibilityElement {
    private weak var node: ChatLayerNode?
    init(node: ChatLayerNode) { self.node = node; super.init() }
    override func isAccessibilityElement() -> Bool {
        guard TGUIKitAccessibility.isEnabled, let node, let scene = node.scene, !scene.isHiddenOrHasHiddenAncestor else { return false }
        return node.isVisible && node.accessibilityRole != nil
    }
    override func accessibilityRole() -> NSAccessibility.Role? { node?.accessibilityRole }
    override func accessibilityLabel() -> String? { node?.accessibilityLabel }
    override func accessibilityValue() -> Any? { node?.accessibilityValue }
    override func isAccessibilityEnabled() -> Bool { node?.isEffectivelyEnabled ?? false }
    override func accessibilityChildren() -> [Any]? { node?.accessibleChildren() }
    override func accessibilityParent() -> Any? {
        guard let node, let scene = node.scene else { return nil }
        var parent = node.parent
        while let value = parent {
            if value.accessibilityRole != nil {
                if value.accessibilityElement == nil { value.accessibilityElement = ChatLayerAccessibilityElement(node: value) }
                return value.accessibilityElement
            }
            parent = value.parent
        }
        return NSAccessibility.unignoredAncestor(of: scene)
    }
    override func accessibilityFrame() -> NSRect {
        guard let node, let scene = node.scene, let window = scene.window else { return .zero }
        let local = node.layer.convert(node.layer.bounds, to: scene.root.layer)
        return window.convertToScreen(scene.convert(local, to: nil))
    }
    override func accessibilityPerformPress() -> Bool {
        guard isAccessibilityElement(), isAccessibilityEnabled() else { return false }
        return node?.onAccessibilityPress?() ?? false
    }
}
