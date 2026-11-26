import Cocoa

public struct TextLayout {
    var layoutSize: NSSize
}

public struct Icon {
    var backingSize: NSSize
}

public struct StatusIcons {
    var sizes: [NSSize] = Array(repeating: NSSize(width: 12, height: 12), count: 7)

    func repliesCountIcon(_ item: ChatRowItem) -> Icon { Icon(backingSize: sizes[0]) }
    func messagePinnedIcon(_ item: ChatRowItem) -> Icon { Icon(backingSize: sizes[1]) }
    func channelViewsIcon(_ item: ChatRowItem) -> Icon { Icon(backingSize: sizes[2]) }
    func paidMessageIcon(_ item: ChatRowItem) -> Icon { Icon(backingSize: sizes[3]) }
    func stateStateIcon(_ item: ChatRowItem) -> Icon { Icon(backingSize: sizes[4]) }
    func readStateIcon(_ item: ChatRowItem) -> Icon { Icon(backingSize: sizes[5]) }
    func diceStakeIcon(_ item: ChatRowItem) -> Icon { Icon(backingSize: sizes[6]) }
}

public struct FailureIcons {
    var sentFailed = Icon(backingSize: NSSize(width: 12, height: 12))
}

public struct Presentation {
    var chat = StatusIcons()
    var icons = FailureIcons()
}

public struct Interaction {
    var isLogInteraction = false
}

public struct ChatRowItem {
    var isStateOverlayLayout = false
    var isBubbled = false
    var isIncoming = false
    var isUnsent = false
    var isFailed = false
    var isRead = false
    var hasSource = false
    var isPinned = false
    var messageEffect: Bool?
    var replyCount: TextLayout?
    var channelViews: TextLayout?
    var postAuthor: TextLayout?
    var editedLabel: TextLayout?
    var paidMessage: TextLayout?
    var date: TextLayout?
    var diceStake: TextLayout?
    var presentation = Presentation()
    var chatInteraction = Interaction()

    init(flags: Int = 0, textWidth: CGFloat = 30) {
        func enabled(_ bit: Int) -> Bool { flags & (1 << bit) != 0 }
        func text(_ bit: Int) -> TextLayout? {
            enabled(bit) ? TextLayout(layoutSize: NSSize(width: textWidth, height: 12)) : nil
        }
        isStateOverlayLayout = enabled(0)
        isBubbled = enabled(1)
        isIncoming = enabled(2)
        isUnsent = enabled(3)
        isFailed = enabled(4)
        chatInteraction.isLogInteraction = enabled(5)
        isRead = enabled(6)
        hasSource = enabled(7)
        messageEffect = enabled(8) ? true : nil
        replyCount = text(9)
        isPinned = enabled(10)
        channelViews = text(11)
        postAuthor = text(12)
        editedLabel = text(13)
        paidMessage = text(14)
        date = text(15)
        diceStake = text(16)
    }
}

public enum System {
    static var backingScale: CGFloat = 2
}
