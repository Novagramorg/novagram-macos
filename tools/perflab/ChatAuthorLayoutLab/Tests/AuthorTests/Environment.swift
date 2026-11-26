import Cocoa
import TGUIKit

enum MonoforumState { case vertical, horizontal }
final class ReplyFixture {
    var isSideAccessory = true
    var size = NSSize(width: 200, height: 50)
    var width: CGFloat = 200
    var sizeToFit = true
    var topOffset: CGFloat = 0
    var calls: [(CGFloat, Bool, CGFloat)] = []
    func measureSize(_ width: CGFloat, sizeToFit: Bool) {
        calls.append((width, sizeToFit, topOffset))
    }
}
class AuthorEnvironment {
    var forwardNameLayout: TextViewLayout?
    var authorText: TextViewLayout?
    var adminBadge: TextViewLayout?
    var boostBadge: TextViewLayout?
    var replyModel: ReplyFixture?
    var isBubbled = true
    var hasBubble = true
    var canFillAuthorName = true
    var _contentSize = NSSize(width: 100, height: 50)
    var monoforumState = MonoforumState.horizontal
}
