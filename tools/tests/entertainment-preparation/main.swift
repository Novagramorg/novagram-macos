import Foundation
import AppKit
import SwiftSignalKit

final class TestWindow { var frame = NSMakeRect(0, 0, 1000, 800) }
final class TestContext { let window = TestWindow() }
final class TestView { var window: TestWindow? }
final class Controller {
    let context = TestContext()
    let view = TestView()
    var popover: NSObject?
    let ready = Promise<Bool>()
    let preparationDisposable = MetaDisposable()
    var loadCount = 0
    var loadedSize = NSSize.zero
    var disappearanceCount = 0
    func isLoaded() -> Bool { return loadCount > 0 }
    func loadViewIfNeeded(_ frame: NSRect) {
        precondition(Thread.isMainThread)
        loadCount += 1
        loadedSize = frame.size
    }
    func viewWillDisappear(_ animated: Bool) { disappearanceCount += 1 }
    func viewDidDisappear(_ animated: Bool) { disappearanceCount += 1 }
__PREPARATION__
    deinit { preparationDisposable.dispose() }
}
func drain() {
    let deadline = Date().addingTimeInterval(0.05)
    while Date() < deadline { RunLoop.current.run(until: deadline) }
}
let hidden = Controller()
hidden.prepareForPresentation()
hidden.prepareForPresentation()
precondition(hidden.loadCount == 0, "Preparation must yield to the chat opening")
drain()
precondition(hidden.loadCount == 1, "Repeated requests must load once")
precondition(hidden.loadedSize == NSMakeSize(350, 550), "Prepare at popover size")
precondition(hidden.disappearanceCount == 0, "Do not pause before initial data is ready")
hidden.ready.set(.single(false))
precondition(hidden.disappearanceCount == 0)
hidden.ready.set(.single(true))
precondition(hidden.disappearanceCount == 2, "Pause prepared content while hidden")
hidden.prepareForPresentation()
drain()
precondition(hidden.loadCount == 1, "Reuse the prepared controller")
let visible = Controller()
visible.prepareForPresentation()
drain()
visible.view.window = visible.context.window
visible.ready.set(.single(true))
precondition(visible.disappearanceCount == 0, "Do not pause an attached sidebar")
let hovered = Controller()
hovered.prepareForPresentation()
drain()
hovered.popover = NSObject()
hovered.ready.set(.single(true))
precondition(hovered.disappearanceCount == 0, "Do not pause an opening popover")
let narrow = Controller()
narrow.context.window.frame.size.height = 500
narrow.prepareForPresentation()
drain()
precondition(narrow.loadedSize.height == 300, "Respect minimum popover height")
var released: Controller? = Controller()
weak var weakController = released
released?.prepareForPresentation()
released = nil
drain()
precondition(weakController == nil, "Queued preparation must not retain a closed account")
print("Passed emoji preparation: deferred loading, size, deduplication, readiness, hidden pause, sidebar/popover handoff, and lifetime")
