import Cocoa
import TGUIKit

private let labImages = ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"].map { name in
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor.white.setFill()
        rect.insetBy(dx: 4, dy: 4).fill()
        return true
    }
    image.setName(name)
    return image
}
func initializeLab() {
    _ = NSApplication.shared
    _ = labImages
    System.updateScaleFactor(2)
    System.liquidGlass = false
}
struct HeaderItem {
    final class ActionItem {
        let title: TextViewLayout
        let context: any AccountContextProtocol = TestAccount()
        init(_ text: String = "Transfer") {
            title = TextViewLayout(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white]))
            title.measure(width: 100)
        }
        let image = NSImage(named: "Icon_SearchField")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        var action: () -> Void = {}
    }
}
enum LiteType { case emoji }
extension AccountContextProtocol {
    func isLite(_ type: LiteType) -> Bool { false }
}
final class InlineTextRenderer {
    func update(textView: TextView, layout: TextViewLayout, context: any AccountContextProtocol, insetEmoji: CGFloat, emojiOffset: NSPoint, decreaseAvatar: CGFloat) {}
    func clear() {}
    func updateAnimatableContent(window: NSWindow?, isLite: Bool) {}
}
struct GeneralRowsHooks {
    static let shared = GeneralRowsHooks()
    func makeInlineTextRenderer() -> InlineTextRenderer { InlineTextRenderer() }
}
struct QrStudioAppearanceReveal {
    func makeMask(frame: CGRect) -> CALayer { CALayer() }
}
func qrStudioTinted(_ image: CGImage?, color: NSColor) -> CGImage? { image?.highlight(color: color) }
