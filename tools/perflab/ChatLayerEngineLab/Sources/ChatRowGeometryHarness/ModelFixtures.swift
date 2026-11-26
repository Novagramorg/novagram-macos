import Cocoa

struct GeometryMode { var isThreadMode = false }
struct GeometryLocation { var threadMsgId: Int? }
struct GeometryInteraction {
    var mode = GeometryMode()
    var chatLocation = GeometryLocation()
}
struct GeometryMessage { let id: Int }
enum ForwardItemType { case ShortHeader, FullHeader, Inside, Bottom }
struct GeometryAccessory { var size: NSSize }
struct GeometryText { var layoutSize: NSSize }
class GeometryCaptionLayout {
    var measuredSize = NSSize(width: 100, height: 40)
    var sizeReads = 0
    var size: NSSize { sizeReads += 1; return measuredSize }
}

public class ChatRowItem {
    public class RowCaption {
        var offset = NSPoint(x: 0, y: 8)
        var layout = GeometryCaptionLayout()
        var contentInset: CGFloat = 6
        var invertedOffset: CGFloat { offset.y + layout.size.height + contentInset }
    }
    var bubbleFrame: NSRect = .zero
    var contentOffset: NSPoint = .zero
    var contentSize: NSSize = .zero
    var rightSize: NSSize = .zero
    var leftInset: CGFloat = 13
    var rightInset: CGFloat = 12
    var defaultContentTopOffset: CGFloat = 10
    var bubbleContentInset: CGFloat = 11
    var additionBubbleInset: CGFloat = 6
    var isIncoming = true
    var isBubbled = true
    var hasBubble = true
    var isStateOverlayLayout = false
    var commentsBubbleData: Int?
    var message: GeometryMessage?
    var chatInteraction = GeometryInteraction()
    var height: CGFloat = 300
    var elementsContentInset: CGFloat = 4
    var topInset: CGFloat = 2
    var leftContentInset: CGFloat = 12
    var defLeftInset: CGFloat = 13
    var defaultContentInnerInset: CGFloat = 6
    var invertMedia = false
    var forwardType: ForwardItemType?
    var forwardNameInset = NSPoint(x: 20, y: 24)
    var forwardHeaderInset = NSPoint(x: 20, y: 8)
    var forwardHeader: GeometryText?
    var authorText: GeometryText?
    var replyModel: GeometryAccessory?
    var topicLinkLayout: GeometryAccessory?
    var replyOffset: CGFloat = 30
    var topicLinkOffset: CGFloat = 60
    var isSharable = false
    var hasSource = false
    var commentsBubbleDataOverlay: Int?
    static let channelCommentsBubbleHeight: CGFloat = 42
}

public final class ChatVideoMessageItem: ChatRowItem {
    var canTranscribe = false
}

public final class ChatMessageItem: ChatRowItem {
    var containsBigEmoji = false
    var actionButtonText: String?
    var webpageLayout: Int?
    var actionButtonHeight: CGFloat = 30
}

public class GeometryView {
    var frame: NSRect
    init(frame: NSRect) { self.frame = frame }
    func focus(_ size: NSSize) -> NSRect {
        return NSRect(x: round((frame.width - size.width) / 2), y: round((frame.height - size.height) / 2), width: size.width, height: size.height)
    }
}
