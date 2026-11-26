import Cocoa
import TGUIKit

let emojiSelectionOrderBadgeSide: CGFloat = 13
let emojiSelectionOrderCircleSide: CGFloat = 30

func emojiSelectionOrderBadgeFrame(selection: CGRect) -> CGRect {
    return NSMakeRect(selection.maxX - emojiSelectionOrderBadgeSide, selection.minY, emojiSelectionOrderBadgeSide, emojiSelectionOrderBadgeSide)
}

func emojiSelectionKey(_ emoji: String) -> String {
    return String(String.UnicodeScalarView(emoji.unicodeScalars.filter { $0.value != 0xFE0F && $0.value != 0xFE0E }))
}

private var emojiSelectionOrderBadgeCache: [String: CGImage] = [:]

func emojiSelectionOrderBadge(_ order: Int, color: NSColor) -> CGImage? {
    let key = "\(order)-\(color.argb)"
    if let image = emojiSelectionOrderBadgeCache[key] {
        return image
    }
    let textNode = TextNode.layoutText(.initialize(string: "\(order)", color: .white, font: .avatar(9)), nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, 20), nil, false, .center)
    let size = NSMakeSize(emojiSelectionOrderBadgeSide, emojiSelectionOrderBadgeSide)
    let image = generateImage(size, rotatedContext: { size, ctx in
        let rect = NSMakeRect(0, 0, size.width, size.height)
        ctx.clear(rect)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: rect)
        textNode.1.draw(rect.focus(textNode.0.size), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
    })
    if let image {
        emojiSelectionOrderBadgeCache[key] = image
    }
    return image
}
