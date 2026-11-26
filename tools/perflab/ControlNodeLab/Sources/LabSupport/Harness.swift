import Cocoa
import ObjectiveC
import TGUIKit

public final class LabWindow: NSWindow {
    public var pointer: NSPoint = .zero
    public override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
}

private let labImages: [NSImage] = ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"].map { name in
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor.black.setFill()
        rect.insetBy(dx: 4, dy: 4).fill()
        return true
    }
    image.setName(name)
    return image
}

public enum LabPointer {
    public static var pressedButtons: Int = 0
    private static var installed = false
    public static func install() {
        guard !installed else { return }
        installed = true
        _ = NSApplication.shared
        _ = labImages
        System.updateScaleFactor(2)
        System.liquidGlass = false
        System.legacyMenu = false
        let method = class_getClassMethod(NSEvent.self, #selector(getter: NSEvent.pressedMouseButtons))!
        let block: @convention(block) (AnyObject) -> Int = { _ in LabPointer.pressedButtons }
        method_setImplementation(method, imp_implementationWithBlock(block))
        let add = class_getInstanceMethod(NSView.self, NSSelectorFromString("addToolTipRect:owner:userData:"))!
        let labAdd = class_getInstanceMethod(NSView.self, #selector(NSView.lab_addToolTipRect(_:owner:userData:)))!
        method_exchangeImplementations(add, labAdd)
        let remove = class_getInstanceMethod(NSView.self, NSSelectorFromString("removeToolTip:"))!
        let labRemove = class_getInstanceMethod(NSView.self, #selector(NSView.lab_removeToolTip(_:)))!
        method_exchangeImplementations(remove, labRemove)
    }
}

public enum ToolTipRecorder {
    public static var live: [(view: ObjectIdentifier, tag: Int, rect: NSRect)] = []
    public static var calls: [String] = []
    public static func rects(for view: NSView) -> [NSRect] {
        live.filter { $0.view == ObjectIdentifier(view) }.map(\.rect)
    }
}

extension NSView {
    @objc func lab_addToolTipRect(_ rect: NSRect, owner: Any, userData: UnsafeMutableRawPointer?) -> NSView.ToolTipTag {
        let tag = lab_addToolTipRect(rect, owner: owner, userData: userData)
        ToolTipRecorder.live.append((ObjectIdentifier(self), tag, rect))
        ToolTipRecorder.calls.append("add \(rect)")
        return tag
    }
    @objc func lab_removeToolTip(_ tag: NSView.ToolTipTag) {
        ToolTipRecorder.live.removeAll { $0.view == ObjectIdentifier(self) && $0.tag == tag }
        ToolTipRecorder.calls.append("remove")
        lab_removeToolTip(tag)
    }
}

public final class RecordingView: View {
    public var record: ((String) -> Void)?
    public override func mouseDown(with event: NSEvent) { record?("next:mouseDown") }
    public override func mouseUp(with event: NSEvent) { record?("next:mouseUp") }
    public override func mouseDragged(with event: NSEvent) { record?("next:mouseDragged") }
    public override func rightMouseDown(with event: NSEvent) { record?("next:rightMouseDown") }
    public override func rightMouseUp(with event: NSEvent) { record?("next:rightMouseUp") }
    public override func rightMouseDragged(with event: NSEvent) { record?("next:rightMouseDragged") }
    public override func mouseMoved(with event: NSEvent) { }
}

public struct HarnessConfig {
    public var events: [ControlEvent] = [.Down, .Up, .Click, .SingleClick, .DoubleClick, .RightDown, .RightUp, .MouseDragging, .LongMouseDown, .LongMouseUp, .LongOver]
    public var states: [ControlState] = [.Normal, .Hover, .Highlight, .Other]
    public var hasContextMenu = false
    public var sendRightMouseAnyway = true
    public var scaleOnClick = false
    public var scaleDownOnClick = false
    public var userInteractionEnabled = true
    public var isEnabled = true
    public init() {}
}

public enum HarnessEvent {
    case moved, down, dragged, up, rightDown, rightUp, exitWindow
}

open class HarnessBase {
    public let window: LabWindow
    public let container: RecordingView
    public let config: HarnessConfig
    public let targetFrame = NSRect(x: 50, y: 50, width: 100, height: 40)
    public var log: [String] = []
    public var closed = false
    private var menus: [ContextMenu] = []
    private var presented = Set<ObjectIdentifier>()

    public init(config: HarnessConfig) {
        LabPointer.install()
        LabPointer.pressedButtons = 0
        Control.lastHandledClickTimestamp = nil
        self.config = config
        window = LabWindow(contentRect: NSRect(x: 200, y: 200, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        container = RecordingView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        window.contentView = container
        container.record = { [weak self] in self?.append($0) }
    }

    public func append(_ entry: String) {
        if !closed { log.append(entry) }
    }

    public func makeMenu() -> ContextMenu {
        append("menu:requested")
        let menu = ContextMenu()
        menus.append(menu)
        return menu
    }

    open var pressLayer: CALayer { fatalError() }
    open func dispatch(_ kind: HarnessEvent, _ event: NSEvent) { fatalError() }

    private func windowPoint(_ point: NSPoint) -> NSPoint {
        return container.convert(point, to: nil)
    }

    private func perform(_ kind: HarnessEvent, _ type: NSEvent.EventType, at point: NSPoint, clickCount: Int, modifiers: NSEvent.ModifierFlags) {
        let location = windowPoint(point)
        window.pointer = location
        let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1)!
        dispatch(kind, event)
        settle()
    }

    private func settle() {
        for menu in menus where menu.observationInfo != nil && !presented.contains(ObjectIdentifier(menu)) {
            presented.insert(ObjectIdentifier(menu))
            append("menu:presented")
        }
        if Control.lastHandledClickTimestamp != nil {
            append("clickTimestamp")
            Control.lastHandledClickTimestamp = nil
        }
    }

    public func move(_ point: NSPoint) {
        perform(.moved, .mouseMoved, at: point, clickCount: 0, modifiers: [])
    }
    public func down(_ point: NSPoint, clickCount: Int = 1, modifiers: NSEvent.ModifierFlags = []) {
        LabPointer.pressedButtons = 1
        perform(.down, .leftMouseDown, at: point, clickCount: clickCount, modifiers: modifiers)
    }
    public func drag(_ point: NSPoint) {
        perform(.dragged, .leftMouseDragged, at: point, clickCount: 1, modifiers: [])
    }
    public func up(_ point: NSPoint, clickCount: Int = 1, modifiers: NSEvent.ModifierFlags = []) {
        LabPointer.pressedButtons = 0
        perform(.up, .leftMouseUp, at: point, clickCount: clickCount, modifiers: modifiers)
    }
    public func rightDown(_ point: NSPoint, clickCount: Int = 1) {
        LabPointer.pressedButtons = 2
        perform(.rightDown, .rightMouseDown, at: point, clickCount: clickCount, modifiers: [])
    }
    public func rightUp(_ point: NSPoint) {
        LabPointer.pressedButtons = 0
        perform(.rightUp, .rightMouseUp, at: point, clickCount: 1, modifiers: [])
    }
    public func exitWindow() {
        let location = NSPoint(x: -100, y: -100)
        window.pointer = location
        let event = NSEvent.mouseEvent(with: .mouseMoved, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 1)!
        dispatch(.exitWindow, event)
        settle()
    }
    public func wait(_ seconds: Double) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
        settle()
    }
    public func moveWindow() {
        window.setFrameOrigin(NSPoint(x: window.frame.minX + 40, y: window.frame.minY))
    }
    public func recordAnimations() {
        let keys = (pressLayer.animationKeys() ?? []).sorted()
        for key in keys {
            guard let animation = pressLayer.animation(forKey: key) else { continue }
            var parts = ["animation", key, String(describing: type(of: animation)), "\(animation.duration)", "removed=\(animation.isRemovedOnCompletion)"]
            if let basic = animation as? CABasicAnimation {
                parts.append("\(basic.keyPath ?? "")")
                parts.append(describe(basic.fromValue))
                parts.append(describe(basic.toValue))
            }
            append(parts.joined(separator: " "))
        }
        if keys.isEmpty { append("animation none") }
    }
    private func describe(_ value: Any?) -> String {
        if let value = value as? NSValue, String(cString: value.objCType).contains("CATransform3D") {
            let t = value.caTransform3DValue
            return "scale(\(t.m11),\(t.m22)) translate(\(t.m41),\(t.m42))"
        }
        return value.map { "\($0)" } ?? "nil"
    }
    public func finish() -> [String] {
        let result = log
        closed = true
        window.contentView = nil
        window.close()
        return result
    }
}

public final class LabControl: Control {
    public var rightAnyway = true
    public override var sendRightMouseAnyway: Bool { rightAnyway }
}

public final class ControlHarness: HarnessBase {
    public let control: LabControl
    private var inside = false

    public override init(config: HarnessConfig) {
        LabPointer.install()
        control = LabControl(frame: NSRect(x: 50, y: 50, width: 100, height: 40))
        super.init(config: config)
        container.addSubview(control)
        control.rightAnyway = config.sendRightMouseAnyway
        control.scaleOnClick = config.scaleOnClick
        control.scaleDownOnClick = config.scaleDownOnClick
        control.userInteractionEnabled = config.userInteractionEnabled
        control.isEnabled = config.isEnabled
        for event in config.events {
            control.set(handler: { [weak self] _ in self?.append("event:\(event)") }, for: event)
        }
        for state in config.states {
            control.set(handler: { [weak self] control in self?.append("state:\(state) now=\(control.controlState)") }, for: state)
        }
        if config.hasContextMenu {
            control.contextMenu = { [weak self] in self?.makeMenu() }
        }
    }

    public override var pressLayer: CALayer { control.layer! }

    public override func dispatch(_ kind: HarnessEvent, _ event: NSEvent) {
        let local = container.convert(event.locationInWindow, from: nil)
        let nowInside = kind != .exitWindow && targetFrame.contains(local)
        if nowInside != inside, LabPointer.pressedButtons == 0, kind == .moved || kind == .exitWindow {
            inside = nowInside
            if nowInside { control.mouseEntered(with: event) } else { control.mouseExited(with: event) }
        }
        switch kind {
        case .moved: if nowInside { control.mouseMoved(with: event) }
        case .down: if nowInside { control.mouseDown(with: event) } else { container.mouseDown(with: event) }
        case .dragged: control.mouseDragged(with: event)
        case .up: control.mouseUp(with: event)
        case .rightDown: if nowInside { control.rightMouseDown(with: event) } else { container.rightMouseDown(with: event) }
        case .rightUp: control.rightMouseUp(with: event)
        case .exitWindow: break
        }
    }
}
