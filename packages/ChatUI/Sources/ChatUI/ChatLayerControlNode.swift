import Cocoa
import TGUIKit
import SwiftSignalKit

private let longHandleDisposable = MetaDisposable()
private let longOverHandleDisposable = MetaDisposable()
private weak var longHandleOwner: ChatLayerControlNode?
private weak var longOverHandleOwner: ChatLayerControlNode?

final class ChatLayerControlNode: ChatLayerNode {
    private struct EventHandler {
        let identifier: UInt32
        let handler: (ChatLayerControlNode) -> Void
        let event: ControlEvent
    }
    private struct StateHandler {
        let identifier: UInt32
        let handler: (ChatLayerControlNode) -> Void
        let state: ControlState
    }

    private final class ToolTipOwner: NSObject, NSViewToolTipOwner {
        weak var node: ChatLayerControlNode?
        func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
            return node?.toolTip ?? ""
        }
    }

    static let longPressDelay: Double = 0.35

    private var handlers: [EventHandler] = []
    private var stateHandlers: [StateHandler] = []
    private var backgroundState: [ControlState: NSColor] = [:]
    private var cursorState: [ControlState: NSCursor] = [:]
    private var longInvoked: Bool = false
    private var mouseDownWindowOrigin: NSPoint?
    private var previousState: ControlState?
    private var controlEnabled: Bool = true

    private let toolTipOwner = ToolTipOwner()
    private weak var toolTipScene: ChatLayerSceneView?
    private var toolTipTag: NSView.ToolTipTag?
    private var toolTipRect: NSRect = .zero
    private var toolTipGeometryVersion: UInt64 = 0

    var contextObject: Any?
    var contextMenu: (() -> ContextMenu?)? = nil
    var sendRightMouseAnyway: Bool = true
    var scaleOnClick: Bool = false
    var scaleDownOnClick: Bool = false
    var handleLongEvent: Bool = true
    var canHighlight: Bool = true
    var moveNextEventDeep: Bool = false
    var controlOpacityEventIgnored: Bool = false
    var userInteractionEnabled: Bool = true

    var toolTip: String? {
        didSet { if toolTip != oldValue { synchronizeToolTip(force: false) } }
    }

    var hasHandlers: Bool { !handlers.isEmpty }

    var controlIsHidden: Bool {
        return isHidden || (layer.opacity < 0.5 && !controlOpacityEventIgnored)
    }

    override var isEnabled: Bool {
        get { controlEnabled }
        set {
            let oldValue = controlEnabled
            controlEnabled = newValue
            if newValue != oldValue { apply(state: controlState) }
        }
    }

    override var isEffectivelyEnabled: Bool { parent?.isEffectivelyEnabled ?? true }

    var isSelected: Bool = false {
        didSet {
            updateState()
            if isSelected != oldValue {
                apply(state: isSelected ? .Highlight : controlState)
            }
        }
    }

    private(set) var controlState: ControlState = .Normal {
        didSet {
            stateDidUpdate(controlState)
            for value in stateHandlers where value.state == .Other {
                value.handler(self)
            }
            if oldValue != controlState {
                for value in stateHandlers where value.state == controlState {
                    value.handler(self)
                }
            }
            apply(state: isSelected ? .Highlight : controlState)
        }
    }

    override init(id: AnyHashable, layer: SimpleLayer = SimpleLayer()) {
        super.init(id: id, layer: layer)
        acceptsPointerEvents = true
        toolTipOwner.node = self
        onPointer = { [weak self] event in self?.handle(event) ?? false }
    }

    deinit {
        if let tag = toolTipTag { toolTipScene?.removeToolTip(tag) }
    }

    override var frame: NSRect {
        get { super.frame }
        set {
            super.frame = newValue
            synchronizeToolTip(force: false)
        }
    }

    override func updateFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        super.updateFrame(frame, transition: transition)
        synchronizeToolTip(force: false)
    }

    override func attach(to scene: ChatLayerSceneView?) {
        let changed = self.scene !== scene
        super.attach(to: scene)
        if changed {
            if scene == nil {
                cancelTracking()
                controlState = .Normal
            }
            synchronizeToolTip(force: false)
        }
    }

    @discardableResult func set(handler: @escaping (ChatLayerControlNode) -> Void, for event: ControlEvent) -> UInt32 {
        let new = EventHandler(identifier: arc4random(), handler: handler, event: event)
        handlers.append(new)
        return new.identifier
    }

    @discardableResult func set(handler: @escaping (ChatLayerControlNode) -> Void, for state: ControlState) -> UInt32 {
        let new = StateHandler(identifier: arc4random(), handler: handler, state: state)
        stateHandlers.append(new)
        return new.identifier
    }

    @discardableResult func setSingle(handler: @escaping (ChatLayerControlNode) -> Void, for event: ControlEvent) -> UInt32 {
        removeAllHandlers()
        return set(handler: handler, for: event)
    }

    func removeHandler(_ identifier: UInt32) {
        handlers.removeAll(where: { $0.identifier == identifier })
    }

    func removeStateHandler(_ identifier: UInt32) {
        stateHandlers.removeAll(where: { $0.identifier == identifier })
    }

    func removeAllHandlers() {
        handlers.removeAll()
    }

    func removeAllStateHandlers() {
        stateHandlers.removeAll()
    }

    func set(background: NSColor, for state: ControlState) {
        backgroundState[state] = background
        apply(state: controlState)
    }

    func set(cursor: NSCursor, for state: ControlState) {
        cursorState[state] = cursor
        apply(state: controlState)
    }

    func send(event: ControlEvent) {
        for value in handlers where value.event == event {
            value.handler(self)
        }
    }

    func showContextMenu() {
        if let menu = contextMenu?(), let event = NSApp.currentEvent {
            present(menu, event: event)
        }
    }

    func apply(state: ControlState) {
        let state: ControlState = isSelected ? .Highlight : state
        if !backgroundState.isEmpty {
            let color = isEnabled ? (backgroundState[state] ?? backgroundState[.Normal]) : backgroundState[.Normal]
            layer.backgroundColor = color?.cgColor
        }
        if !cursorState.isEmpty {
            cursor = cursorState[state] ?? .arrow
        }
    }

    func updateState() {
        if mouseInside(), scene?.inLiveResize != true {
            if mouseIsDown && canHighlight {
                controlState = .Highlight
            } else {
                controlState = .Hover
            }
        } else {
            controlState = .Normal
        }
    }

    func mouseInside() -> Bool {
        guard let scene, scene.node(id: id) === self, let window = scene.window else { return false }
        let location = window.mouseLocationOutsideOfEventStream
        guard window.contentView?.hitTest(location) === scene else { return false }
        var node = scene.hitNode(at: scene.convert(location, from: nil))
        while let current = node {
            if current === self { return true }
            node = current.parent
        }
        return false
    }

    private var mouseIsDown: Bool {
        return (NSEvent.pressedMouseButtons & (1 << 0)) != 0
    }

    private func stateDidUpdate(_ state: ControlState) {
        if scaleOnClick || scaleDownOnClick {
            if state != previousState, isEnabled {
                let pressed: CGFloat = scaleDownOnClick ? 0.97 : 1.03
                if state == .Highlight {
                    layer.animateScaleSpring(from: 1, to: pressed, duration: 0.3, removeOnCompletion: false)
                } else if layer.animation(forKey: "transform") != nil, previousState == .Highlight {
                    layer.animateScaleSpring(from: pressed, to: 1.0, duration: 0.3)
                }
            }
        }
        previousState = state
    }

    private func present(_ menu: ContextMenu, event: NSEvent) {
        guard let scene else { return }
        let onShow = menu.onShow
        let onClose = menu.onClose
        menu.onShow = { [weak self] menu in
            onShow(menu)
            self?.isSelected = true
        }
        menu.onClose = { [weak self] in
            onClose()
            self?.isSelected = false
        }
        AppMenu.show(menu: menu, event: event, for: scene)
    }

    private func forward(_ event: ChatLayerPointerEvent) {
        guard let native = event.nativeEvent, let responder = scene?.nextResponder else { return }
        switch (event.kind, event.button) {
        case (.down, 0): responder.mouseDown(with: native)
        case (.dragged, 0): responder.mouseDragged(with: native)
        case (.up, 0): responder.mouseUp(with: native)
        case (.down, 1): responder.rightMouseDown(with: native)
        case (.dragged, 1): responder.rightMouseDragged(with: native)
        case (.up, 1): responder.rightMouseUp(with: native)
        default: break
        }
    }

    private func cancelTracking() {
        if longHandleOwner === self { longHandleDisposable.set(nil) }
        if longOverHandleOwner === self { longOverHandleDisposable.set(nil) }
        mouseDownWindowOrigin = nil
    }

    private func handle(_ event: ChatLayerPointerEvent) -> Bool {
        if let scene, toolTip != nil, toolTipGeometryVersion != scene.geometryVersion {
            synchronizeToolTip(force: false)
        }
        switch event.kind {
        case .entered:
            if NSEvent.pressedMouseButtons != 0 { return true }
            mouseEntered()
            return true
        case .exited:
            if NSEvent.pressedMouseButtons != 0 { return true }
            updateState()
            longOverHandleDisposable.set(nil)
            return true
        case .moved:
            updateState()
            return userInteractionEnabled
        case .cancelled:
            cancelTracking()
            controlState = .Normal
            return true
        case .down:
            switch event.button {
            case 0: return mouseDown(event)
            case 1: return rightMouseDown(event)
            default: return false
            }
        case .dragged:
            switch event.button {
            case 0: mouseDragged(event)
            default: forward(event)
            }
            return true
        case .up:
            switch event.button {
            case 0: mouseUp(event)
            case 1: rightMouseUp(event)
            default: forward(event)
            }
            return true
        }
    }

    private func mouseEntered() {
        updateState()
        if userInteractionEnabled {
            let disposable = (Signal<Void, Void>.single(Void()) |> delay(0.3, queue: Queue.mainQueue())).start(next: { [weak self] in
                if let self, self.mouseInside(), self.controlState == .Hover {
                    self.send(event: .LongOver)
                }
            })
            longOverHandleOwner = self
            longOverHandleDisposable.set(disposable)
        }
    }

    private func mouseDown(_ event: ChatLayerPointerEvent) -> Bool {
        longInvoked = false
        mouseDownWindowOrigin = scene?.window?.frame.origin
        longOverHandleDisposable.set(nil)

        if event.modifiers.contains(.control) {
            if let menu = contextMenu?(), event.clickCount == 1, let native = event.nativeEvent {
                present(menu, event: native)
            }
            send(event: .RightDown)
            if sendRightMouseAnyway {
                forward(event)
            }
            return true
        }

        guard userInteractionEnabled else { return false }
        updateState()
        updateState()
        send(event: .Down)
        if handleLongEvent, let native = event.nativeEvent {
            let point = native.locationInWindow
            let disposable = (Signal<Void, Void>.single(Void()) |> delay(ChatLayerControlNode.longPressDelay, queue: Queue.mainQueue())).start(next: { [weak self] in
                self?.invokeLongDown(native, point: point)
            })
            longHandleOwner = self
            longHandleDisposable.set(disposable)
        } else {
            longHandleDisposable.set(nil)
        }
        return true
    }

    private func invokeLongDown(_ event: NSEvent, point: NSPoint) {
        if mouseInside(), let wPoint = scene?.window?.mouseLocationOutsideOfEventStream, NSPointInRect(point, NSMakeRect(wPoint.x - 2, wPoint.y - 2, 4, 4)) {
            longInvoked = true
            if let menu = contextMenu?(), !handlers.contains(where: { $0.event == .LongMouseDown }) {
                present(menu, event: event)
            }
            send(event: .LongMouseDown)
        }
    }

    private func mouseDragged(_ event: ChatLayerPointerEvent) {
        if let start = mouseDownWindowOrigin, let current = scene?.window?.frame.origin, start != current {
            longHandleDisposable.set(nil)
        }
        if userInteractionEnabled {
            send(event: .MouseDragging)
            updateState()
        } else {
            forward(event)
        }
    }

    private func mouseUp(_ event: ChatLayerPointerEvent) {
        longHandleDisposable.set(nil)
        longOverHandleDisposable.set(nil)

        let windowMoved: Bool
        if let start = mouseDownWindowOrigin, let current = scene?.window?.frame.origin {
            windowMoved = start != current
        } else {
            windowMoved = false
        }
        mouseDownWindowOrigin = nil

        if moveNextEventDeep {
            forward(event)
            moveNextEventDeep = false
            return
        }

        if userInteractionEnabled && !event.modifiers.contains(.control) {
            if isEnabled && !controlIsHidden && !windowMoved {
                if !longInvoked, handlers.isEmpty, let menu = contextMenu?(), event.clickCount == 1, let native = event.nativeEvent {
                    present(menu, event: native)
                }
                send(event: .Up)
                if longInvoked {
                    send(event: .LongMouseUp)
                }
                if mouseInside() && !longInvoked {
                    if event.clickCount == 1 {
                        send(event: .SingleClick)
                    }
                    if event.clickCount == 2 {
                        send(event: .DoubleClick)
                    }
                    send(event: .Click)
                    Control.lastHandledClickTimestamp = CACurrentMediaTime()
                }
            }
            updateState()
        } else {
            if userInteractionEnabled && event.modifiers.contains(.control) {
                send(event: .RightUp)
                return
            }
            forward(event)
        }
    }

    private func rightMouseDown(_ event: ChatLayerPointerEvent) -> Bool {
        if let menu = contextMenu?(), event.clickCount == 1, userInteractionEnabled, let native = event.nativeEvent {
            present(menu, event: native)
            return true
        }
        guard userInteractionEnabled else { return false }
        updateState()
        send(event: .RightDown)
        if sendRightMouseAnyway {
            forward(event)
        }
        return true
    }

    private func rightMouseUp(_ event: ChatLayerPointerEvent) {
        if userInteractionEnabled {
            updateState()
            send(event: .RightUp)
        } else {
            forward(event)
        }
    }

    private var sceneFrame: NSRect? {
        guard scene != nil else { return nil }
        var rect = frame
        var current = parent
        while let node = current {
            rect = rect.offsetBy(dx: node.frame.minX - node.layer.bounds.minX, dy: node.frame.minY - node.layer.bounds.minY)
            current = node.parent
        }
        return rect
    }

    private func synchronizeToolTip(force: Bool) {
        guard let scene, toolTip != nil, let rect = sceneFrame, !rect.isEmpty else {
            removeToolTip()
            return
        }
        toolTipGeometryVersion = scene.geometryVersion
        if !force, toolTipScene === scene, toolTipRect == rect, toolTipTag != nil { return }
        removeToolTip()
        toolTipScene = scene
        toolTipRect = rect
        toolTipTag = scene.addToolTip(rect, owner: toolTipOwner, userData: nil)
    }

    private func removeToolTip() {
        if let tag = toolTipTag { toolTipScene?.removeToolTip(tag) }
        toolTipTag = nil
        toolTipScene = nil
        toolTipRect = .zero
    }
}
