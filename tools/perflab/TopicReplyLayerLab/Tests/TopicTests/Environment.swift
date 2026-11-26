import Cocoa
import TGUIKit

protocol AccountContextProtocol: AnyObject {
    var account: FixtureAccount { get }
    var inlinePacksContext: Int { get }
}
final class FixtureAccount { static let shared = FixtureAccount() }
final class FixtureContext: AccountContextProtocol {
    let account: FixtureAccount
    init(account: FixtureAccount = .shared) { self.account = account }
    let inlinePacksContext = 1
}
struct FixtureMediaId { let id: Int64 }
struct FixtureFile {
    let resourceKey: String
    var fileId: FixtureMediaId { FixtureMediaId(id: resourceKey.hasPrefix("general-") ? 523134 : Int64(resourceKey.hashValue)) }
}
typealias TelegramMediaFile = FixtureFile
struct FixtureEmoji {
    let fileId: Int64
    let file: FixtureFile?
    init(fileId: Int64, file: FixtureFile? = nil, emoji: String = "") { self.fileId = fileId; self.file = file }
}
final class InlineStickerItem: NSObject {
    enum Source { case attribute(FixtureEmoji) }
    let source: Source
    init(_ id: Int64, file: FixtureFile? = nil) { source = .attribute(.init(fileId: id, file: file)) }
}
final class InlineStickerItemLayer: SimpleLayer {
    struct Key: Hashable { let id: Int64; let index: Int }
    enum PlayPolicy { case playCount(Int), framesCount(Int) }
    weak var superview: NSView?
    var isPlayable = false
    let fileId: Int64
    let resourceKey: String?
    init(account: FixtureAccount, inlinePacksContext: Int, emoji: FixtureEmoji, size: NSSize, playPolicy: PlayPolicy) {
        fileId = emoji.fileId
        resourceKey = emoji.file?.resourceKey
        super.init()
        frame = size.bounds
        contents = generateImage(size, contextGenerator: { size, context in
            context.clear(size.bounds)
            context.setFillColor(NSColor.red.cgColor)
            context.fill(size.bounds.insetBy(dx: 1, dy: 1))
            context.setFillColor(NSColor.blue.cgColor)
            context.fill(CGRect(x: 1, y: 1, width: size.width / 2, height: size.height / 3))
        })
    }
    override init(layer: Any) { fileId = (layer as! InlineStickerItemLayer).fileId; resourceKey = (layer as! InlineStickerItemLayer).resourceKey; super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }
}
final class TopicReplyItemLayout {
    let context: any AccountContextProtocol
    let text: TextViewLayout
    let iconIdentity: ChatTopicIconIdentity
    let size: NSSize
    init(_ title: String, width: CGFloat = 180, lines: Int32 = 1, id: Int64? = 42, color: NSColor = .blue, background: NSColor = .lightGray, generated: Bool = false, iconColor: Int32 = 1, isGeneral: Bool = false, context: FixtureContext = FixtureContext(), generalColor: NSColor = .gray) {
        self.context = context
        let usesGenerated = generated || id == 0
        iconIdentity = ChatTopicIconIdentity(account: context.account, fileId: usesGenerated ? nil : id, title: title, iconColor: iconColor, isGeneral: isGeneral, generalColor: generalColor, customColor: theme.colors.accent)
        let file = usesGenerated ? FixtureFile(resourceKey: isGeneral ? "general-\(generalColor)" : "generated-\(title.prefix(1))-\(iconColor)") : nil
        let renderId = file.map { fixtureGeneratedIconId($0, FixtureTopicInfo(title: title, iconColor: iconColor, icon: id)) } ?? id
        let value = NSMutableAttributedString(attributedString: .initialize(string: renderId == nil ? title : "🐥 " + title, color: color, font: .normal(13)))
        if let renderId { value.addAttribute(TextInputAttributes.embedded, value: InlineStickerItem(renderId, file: file), range: NSRange(location: 0, length: 2)) }
        text = TextViewLayout(value, maximumNumberOfLines: lines, alignment: .left, alwaysStaticItems: true)
        text.measure(width: width)
        text.generateAutoBlock(backgroundColor: background, minusHeight: 0, yInset: 1)
        size = NSMakeSize(text.layoutSize.width, text.layoutSize.height - 8)
    }
}

final class InlineStickerView: View {
    let animateLayer: InlineStickerItemLayer
    init(account: FixtureAccount, inlinePacksContext: Int, emoji: FixtureEmoji, size: NSSize, playPolicy: InlineStickerItemLayer.PlayPolicy = .playCount(2)) {
        animateLayer = InlineStickerItemLayer(account: account, inlinePacksContext: inlinePacksContext, emoji: emoji, size: size, playPolicy: playPolicy)
        super.init(frame: size.bounds)
        animateLayer.superview = self
        layer?.addSublayer(animateLayer)
    }
    required init(frame: NSRect) { fatalError() }
    required init?(coder: NSCoder) { fatalError() }
}
struct FixtureChatListTheme { var badgeMutedBackgroundColor = NSColor.gray }
struct FixturePalette { var accent = NSColor.blue }
struct FixtureTheme { var chatList = FixtureChatListTheme(); var colors = FixturePalette() }
var theme = FixtureTheme()
final class ChatInterfaceHooks {
    static let shared = ChatInterfaceHooks()
    var fileCalls = 0
    func makeTopicIconFile(_ title: String, _ color: Int32, _ general: Bool) -> TelegramMediaFile {
        fileCalls += 1
        return FixtureFile(resourceKey: general ? "general-\(theme.chatList.badgeMutedBackgroundColor)" : "generated-\(title.prefix(1))-\(color)")
    }
}
struct FixtureTopicInfo { var title: String; var iconColor: Int32; var icon: Int64? }
struct FixtureThreadData { let info: FixtureTopicInfo }
struct FixtureThreadItem { let threadData: FixtureThreadData? }
struct FixtureTopicTab { let uniqueId: Int64; let item: FixtureThreadItem? }
struct FixtureVerticalItem { let context: FixtureContext; let item: FixtureTopicTab }
class SeparatorEnvironment: View {
    var iconView: InlineStickerView?
    var avatarView: View?
    var topicIconIdentity: ChatTopicIconIdentity?
    let containerView = View()
}
class VerticalEnvironment: View {
    var animatedView: InlineStickerView?
    var photoView: View?
    var imageView: View?
    var topicIconIdentity: ChatTopicIconIdentity?
}
