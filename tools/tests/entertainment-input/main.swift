import AppKit

enum Event: Hashable { case LongOver, Click }
enum Edge { case maxX }
final class Popover {
    var animates = true
    var hidden = false
    func hide() { precondition(!animates); hidden = true }
}
final class Button {
    var frame = NSRect(x: 0, y: 0, width: 40, height: 40)
    var popover: Popover?
    var handlers: [Event: (Button) -> Void] = [:]
    func set(handler: @escaping (Button) -> Void, for event: Event) { handlers[event] = handler }
    func send(_ event: Event) { handlers[event]?(self) }
}
final class Window { var frame = NSRect(x: 0, y: 0, width: 700, height: 800) }
final class Context { let window = Window() }
final class Interaction {
    let interactionContext = Context()
    var toggles = 0
    func toggleSidebar() { toggles += 1 }
}
struct Hooks {
    var available = true
    var visible = false
    func isEntertainmentSidebarAvailable(_ window: Window) -> Bool { available }
    func isEntertainmentSidebarVisible(_ window: Window) -> Bool { visible }
}
enum ChatInputUIHooks { static var shared = Hooks() }
final class View { var frame = NSRect.zero }
final class Controller { var _frameRect = NSRect.zero; let view = View() }
var shown = 0
func showPopover(for button: Button, with controller: Controller, edge: Edge, inset: NSPoint, delayBeforeShown: Double) {
    precondition(controller._frameRect == controller.view.frame)
    precondition(controller.view.frame.width == 350)
    shown += 1
}
final class Harness {
    let entertaiments = Button()
    let chatInteraction = Interaction()
    let window = Window()
    var frame = NSRect(x: 0, y: 0, width: 40, height: 40)
    var controllers = 0
    var entertaimentsPopover: Controller { controllers += 1; return Controller() }
    init() { addHoverObserver(); addClickObserver() }
__HANDLERS__
}
struct Split {
    var lastPaneAvailableWidth: CGFloat
__WIDTH__
}

let h = Harness()
h.entertaiments.send(.LongOver)
precondition(shown == 1 && h.controllers == 1 && h.chatInteraction.toggles == 0)
let popover = Popover()
h.entertaiments.popover = popover
h.entertaiments.send(.Click)
precondition(popover.hidden && h.chatInteraction.toggles == 1)
ChatInputUIHooks.shared.visible = true
h.entertaiments.send(.LongOver)
precondition(shown == 1)
h.entertaiments.send(.Click)
precondition(h.chatInteraction.toggles == 2)
ChatInputUIHooks.shared = Hooks(available: false, visible: false)
h.entertaiments.send(.LongOver)
h.entertaiments.send(.Click)
precondition(shown == 3 && h.controllers == 3 && h.chatInteraction.toggles == 2)
precondition(Split(lastPaneAvailableWidth: 500).additionalWidthForTrailing(width: 358, minimumLeadingWidth: 380) == 238)
precondition(Split(lastPaneAvailableWidth: 738).additionalWidthForTrailing(width: 358, minimumLeadingWidth: 380) == 0)
precondition(Split(lastPaneAvailableWidth: 900).additionalWidthForTrailing(width: 358, minimumLeadingWidth: 380) == 0)
print("Passed: first hover, one popover controller, click handoff, visible panel, popup fallback, and three width cases")
