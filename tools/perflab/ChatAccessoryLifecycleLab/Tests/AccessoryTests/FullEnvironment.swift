import Cocoa
import TGUIKit
import ColorPalette

struct AccessoryPresentation {
    var colors = PeerNameColors.Colors(main: .systemBlue)
    var background = NSColor.clear
    var pattern: Int64?
    var giftEmojiFileId: Int64?
}

class ChatAccessoryModel {
    enum ModelType { case modern, classic }
    var modelType = ModelType.modern
    let context: FixtureContext
    var header: TextViewLayout?
    var message: TextViewLayout?
    var leftInset: CGFloat = 8
    var mediaInset: CGFloat = 0
    var topOffset: CGFloat = 0
    var size = NSSize(width: 250, height: 50)
    var drawLine = true
    var isSideAccessory = false
    var isSummarize = false
    var presentation = AccessoryPresentation()
    var quoteIcon: CGImage?
    var shimm: (NSPoint, CGImage?) = (.zero, nil)
    init(context: FixtureContext = FixtureContext()) { self.context = context }
}

final class ReplyModel: ChatAccessoryModel { var pollIcon: CGImage? }
final class SummarizeReplyModel: ChatAccessoryModel {
    var infoCalls = 0
    func showInfo() { infoCalls += 1 }
}

struct AccessoryStrings { var voiceOverCommonInfo: String { "Info" } }
func strings() -> AccessoryStrings { AccessoryStrings() }

struct TelegramThemeHooks {
    enum Icon { case starReactionParticle, menuCocoon }
    static let shared = TelegramThemeHooks()
    func image(_ icon: Icon) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.white.setFill()
            rect.insetBy(dx: 3, dy: 3).fill()
            return true
        }
    }
}
