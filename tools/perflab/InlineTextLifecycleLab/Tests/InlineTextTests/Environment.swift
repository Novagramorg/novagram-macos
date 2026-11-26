import Cocoa
import TGUIKit

public enum LiteFeature { case emoji }
public protocol AccountContextProtocol { func isLite(_ feature: LiteFeature) -> Bool }
final class FixtureContext: AccountContextProtocol {
    var lite = false
    func isLite(_ feature: LiteFeature) -> Bool { lite }
}
public protocol InlineTextRenderer: AnyObject {
    func update(textView: TextView, layout: TextViewLayout, context: any AccountContextProtocol, insetEmoji: CGFloat, emojiOffset: NSPoint, decreaseAvatar: CGFloat)
    func clear()
    func updateAnimatableContent(window: NSWindow?, isLite: Bool)
}
final class RendererFixture: InlineTextRenderer {
    var updates = 0
    var playbackCalls = 0
    var clears = 0
    var playable = false
    var events: [String] = []
    var recordsEvents = true
    var lastInset: CGFloat = 0
    var lastOffset = NSPoint.zero
    var lastDecrease: CGFloat = 0
    var lastLayout: TextViewLayout?
    func update(textView: TextView, layout: TextViewLayout, context: any AccountContextProtocol, insetEmoji: CGFloat, emojiOffset: NSPoint, decreaseAvatar: CGFloat) {
        updates += 1
        if lastLayout?.embeddedItems.isEmpty != false && !layout.embeddedItems.isEmpty { playable = false }
        if recordsEvents { events.append("update") }
        lastLayout = layout
        lastInset = insetEmoji
        lastOffset = emojiOffset
        lastDecrease = decreaseAvatar
    }
    func clear() {
        clears += 1
        if recordsEvents { events.append("clear") }
        lastLayout = nil
    }
    func updateAnimatableContent(window: NSWindow?, isLite: Bool) {
        playbackCalls += 1
        playable = window?.isKeyWindow == true && !isLite
        if recordsEvents { events.append(playable ? "play" : "stop") }
    }
}
struct GeneralRowsHooks {
    static var shared = GeneralRowsHooks()
    var makeInlineTextRenderer: () -> InlineTextRenderer = { RendererFixture() }
}
