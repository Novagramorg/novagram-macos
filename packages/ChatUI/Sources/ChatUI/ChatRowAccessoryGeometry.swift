import Cocoa

extension ChatRowGeometry {
    struct SideAccessory {
        let contentFrame: NSRect
        let size: NSSize
        let offset: CGFloat
        let elementsInset: CGFloat
        let isOnSide: Bool
        let isIncoming: Bool
        let hasSideAction: Bool
    }

    struct Author {
        let contentFrame: NSRect
        let topOffset: CGFloat
        let topInset: CGFloat
        let elementsInset: CGFloat
        let forwardInset: CGFloat
        let isBubbled: Bool
    }

    struct ForwardName {
        let inset: NSPoint
        let bubbleFrame: NSRect
        let contentFrame: NSRect
        let isBubbled: Bool
        let hasBubble: Bool
        let isIncoming: Bool
        let bubbleInset: CGFloat
        let additionInset: CGFloat
        let accessoryWidth: CGFloat?
        let hasAuthor: Bool
    }

    enum ForwardLineKind: Equatable { case short, full, inside, bottom }

    @inline(__always) static func sideAccessoryFrame(_ input: SideAccessory) -> NSRect {
        var frame = NSRect(x: input.contentFrame.minX + input.elementsInset, y: input.offset, width: input.size.width, height: input.size.height)
        if input.isOnSide {
            frame.origin.x = input.isIncoming ? input.contentFrame.maxX + 6 : input.contentFrame.minX - input.size.width - 6
            if input.hasSideAction { frame.origin.x += input.isIncoming ? 46 : -46 }
        }
        return frame
    }

    @inline(__always) static func authorPoint(_ input: Author) -> NSPoint {
        var point = NSPoint(x: input.contentFrame.minX, y: input.topOffset)
        if input.isBubbled { point.y -= input.topInset - 1 }
        else { point.x -= input.forwardInset }
        point.x += input.elementsInset
        return point
    }

    @inline(__always) static func forwardNamePoint(_ input: ForwardName) -> NSPoint {
        var point = input.inset
        if input.isBubbled && input.hasBubble {
            point.x = input.bubbleFrame.minX + (input.isIncoming ? input.bubbleInset + input.additionInset : input.bubbleInset)
        } else if input.isBubbled, let width = input.accessoryWidth {
            point.x = input.isIncoming ? input.contentFrame.maxX : input.contentFrame.minX - width
            point.y += 2
        }
        if !input.hasAuthor { point.y -= 3 }
        return point
    }

    @inline(__always) static func avatarFrame(leftInset: CGFloat, rowHeight: CGFloat, isBubbled: Bool) -> NSRect {
        return NSRect(x: leftInset, y: isBubbled ? rowHeight - 36 : 6, width: 36, height: 36)
    }

    @inline(__always) static func captionFrame(contentFrame: NSRect, size: NSSize, offset: CGFloat, invertedOffset: CGFloat, contentInset: CGFloat, innerInset: CGFloat, elementsInset: CGFloat, invertMedia: Bool, isBubbled: Bool) -> NSRect {
        var frame = contentFrame
        if invertMedia {
            frame.origin.y -= frame.height
            frame.origin.y -= invertedOffset
            if !isBubbled { frame.origin.y -= contentInset / 2 }
        } else {
            frame.origin.y += offset + innerInset
        }
        return NSRect(x: frame.minX + elementsInset, y: frame.maxY, width: size.width, height: size.height)
    }

    @inline(__always) static func forwardHeaderFrame(leftInset: CGFloat, top: CGFloat, size: NSSize?) -> NSRect {
        guard let size else { return .zero }
        return NSRect(x: leftInset, y: top, width: size.width, height: size.height)
    }

    @inline(__always) static func forwardLineFrame(kind: ForwardLineKind?, rowHeight: CGFloat, leftInset: CGFloat, nameTop: CGFloat, topOffset: CGFloat, isBubbled: Bool) -> NSRect {
        guard let kind, !isBubbled else { return .zero }
        switch kind {
        case .short: return NSRect(x: leftInset, y: nameTop, width: 2, height: rowHeight - nameTop - topOffset)
        case .full: return NSRect(x: leftInset, y: nameTop, width: 2, height: rowHeight - nameTop)
        case .inside: return NSRect(x: leftInset, y: 0, width: 2, height: rowHeight)
        case .bottom: return NSRect(x: leftInset, y: 0, width: 2, height: rowHeight - topOffset)
        }
    }
}
