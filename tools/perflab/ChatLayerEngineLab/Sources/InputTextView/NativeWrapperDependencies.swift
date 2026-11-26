import Cocoa
import TGUIKit

enum ReferenceLiteMode { case emoji }
protocol AccountContextProtocol {
    func isLite(_ mode: ReferenceLiteMode) -> Bool
}
struct ReferenceContext: AccountContextProtocol {
    func isLite(_ mode: ReferenceLiteMode) -> Bool { false }
}

struct FoldingInlineStickers {
    var isEmpty: Bool { true }
    func update(textView: TextView, context: any AccountContextProtocol, textLayout: TextViewLayout) {}
    func updateAnimatableContent(window: NSWindow?, isLite: Bool) {}
}

enum ReferenceIcon { case iconQuote, iconCopyCode }
struct TelegramThemeHooks {
    static let shared = TelegramThemeHooks()
    func image(_ icon: ReferenceIcon) -> NSImage {
        return NSImage(named: icon == .iconQuote ? "Icon_Quote" : "Icon_CopyCode")!
    }
}
