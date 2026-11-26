import AppKit

final class Delegate {
    var view: NSView?
    var calls: [(AnyHashable, Bool)] = []

    func contentInteractionView(for id: AnyHashable, animateIn: Bool) -> NSView? {
        calls.append((id, animateIn))
        return view
    }
}

final class Viewer {
    var firstStableId: AnyHashable? = "message"
    var delegate: Delegate?

    func open(ignoreStableId: AnyHashable?) -> (AnyHashable) -> NSView? {
        let strongSelf: Viewer? = self
        return { [weak strongSelf] stableId -> NSView? in
            __OPEN__
        }
    }

    func close() -> (AnyHashable) -> NSView? {
        return { [weak self] stableId in
            __CLOSE__
        }
    }
}

let direction = CommandLine.arguments[1]
let scenario = CommandLine.arguments[2]
let delegate = Delegate()
let container = NSView()
let first = NSView()
let second = NSView()
container.addSubview(first)
container.addSubview(second)
delegate.view = container
var viewer: Viewer? = Viewer()
viewer?.delegate = delegate
var stableId: AnyHashable = 1
var expected: NSView? = second
var ignore: AnyHashable?

switch scenario {
case "removed-last":
    second.removeFromSuperview()
    expected = nil
case "empty":
    first.removeFromSuperview()
    second.removeFromSuperview()
    expected = nil
case "negative":
    stableId = -1
    expected = nil
case "missing-view":
    delegate.view = nil
    expected = nil
case "missing-owner":
    expected = nil
case "direct":
    viewer?.firstStableId = nil
    stableId = "photo"
    expected = container
case "ignored":
    ignore = stableId
    expected = direction == "open" ? nil : second
case "changed":
    break
default:
    break
}

let resolve = direction == "open" ? viewer!.open(ignoreStableId: ignore) : viewer!.close()
if scenario == "missing-owner" {
    viewer = nil
}
if scenario == "changed" {
    precondition(resolve(stableId) === second)
    second.removeFromSuperview()
    expected = nil
}
let result = resolve(stableId)
precondition(result === expected)
if scenario == "direct" {
    precondition(delegate.calls.last?.0 == stableId)
    precondition(delegate.calls.last?.1 == (direction == "close"))
} else if scenario == "missing-owner" || (scenario == "ignored" && direction == "open") {
    precondition(delegate.calls.isEmpty)
} else {
    precondition(delegate.calls.last?.0 == AnyHashable("message"))
}
