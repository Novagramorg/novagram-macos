import Cocoa

struct MaskPanel {
    var rect: CGRect
    var cornerRadius: CGFloat
    var blurTint: NSColor
    var flatColor: NSColor
    var mask: CGImage?
}

struct ChatRowItem {
    struct Context {
        enum Feature { case blur }
        var lite: Bool
        func isLite(_ feature: Feature) -> Bool { lite }
    }
    var context: Context
    var isIncoming: Bool = true
    var panels: [MaskPanel]
    var bubbleFrame: CGRect = CGRect(x: 7, y: 3, width: 150, height: 100)
}

final class MaskBubbleView: NSView {
    func setCutBands(_ rects: [CGRect], incoming: Bool) {}
}
