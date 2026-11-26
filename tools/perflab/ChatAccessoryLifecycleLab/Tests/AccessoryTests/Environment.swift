import Cocoa
import TGUIKit

enum LiteFeature { case emoji }
protocol AccountContextProtocol {
    var account: Int { get }
    var inlinePacksContext: Int { get }
    func isLite(_ feature: LiteFeature) -> Bool
}
final class FixtureContext: AccountContextProtocol {
    let account = 1
    let inlinePacksContext = 1
    var lite = false
    func isLite(_ feature: LiteFeature) -> Bool { lite }
}
struct FixtureEmoji {
    var fileId: Int64
    init(fileId: Int64, file: Int? = nil, emoji: String = "") { self.fileId = fileId }
}
final class InlineStickerItem: NSObject {
    enum Source { case attribute(FixtureEmoji), other }
    let source: Source
    init(_ id: Int64) { source = .attribute(FixtureEmoji(fileId: id)) }
}
public final class InlineStickerItemLayer: SimpleLayer {
    public struct Key: Hashable {
        public var id: Int64
        public var index: Int
        public var color: NSColor?
    }
    public weak var superview: NSView?
    let textColor: NSColor
    enum PlayPolicy { case framesCount(Int), playCount(Int) }
    var noDelayBeforeplay = false
    public var isPlayable = false
    let fileId: Int64
    init(account: Int, inlinePacksContext: Int, emoji: FixtureEmoji, size: CGSize, playPolicy: PlayPolicy = .playCount(2), textColor: NSColor = .black, contentDidUpdate: ((CGImage?) -> Void)? = nil) {
        self.textColor = textColor
        self.fileId = emoji.fileId
        super.init()
        self.frame = CGRect(origin: .zero, size: size)
    }
    override init(layer: Any) {
        let original = layer as! InlineStickerItemLayer
        textColor = original.textColor
        fileId = original.fileId
        super.init(layer: layer)
    }
    required init?(coder: NSCoder) { fatalError() }
}
struct FixturePalette { var text = NSColor.black }
struct FixtureTheme { var colors = FixturePalette() }
let theme = FixtureTheme()
struct FixtureModel {
    var header: TextViewLayout?
    var message: TextViewLayout?
    let context: FixtureContext
}
class AccessoryBase: View {
    let headerView = TextView()
    var textView: TextView? = TextView()
    var layoutPass = 0
    required init(frame: NSRect) {
        super.init(frame: frame)
        headerView.isSelectable = false
        textView?.isSelectable = false
        addSubview(headerView)
        addSubview(textView!)
    }
    required init?(coder: NSCoder) { fatalError() }
    func updateLayout(_ size: NSSize, transition: ContainedViewLayoutTransition) {
        layoutPass += 1
        headerView.setFrameOrigin(NSPoint(x: 8, y: 2))
        textView?.setFrameOrigin(NSPoint(x: 8, y: 20))
    }
    func updateTheme() {}
}
