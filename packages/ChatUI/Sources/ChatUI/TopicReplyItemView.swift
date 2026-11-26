import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Postbox
import ColorPalette
import TGModernGrowingTextView
import Strings
import TelegramContext
import TelegramTheme
import TelegramUtils
import InlineStickerLayer

struct ChatTopicIconIdentity: Equatable {
    private enum Content: Equatable {
        case custom(Int64, NSColor)
        case generated(String, Int32)
        case general(NSColor)
        case unavailable(Int64)
    }

    private let account: ObjectIdentifier
    private let content: Content

    init(account: AnyObject, fileId: Int64?, title: String?, iconColor: Int32, isGeneral: Bool, generalColor: NSColor, customColor: NSColor, fallbackId: Int64 = 0) {
        self.account = ObjectIdentifier(account)
        if let fileId, fileId != 0 {
            content = .custom(fileId, customColor)
        } else if let title {
            if isGeneral {
                content = .general(generalColor)
            } else {
                content = .generated(String(title.prefix(1)), iconColor)
            }
        } else {
            content = .unavailable(fallbackId)
        }
    }
}

public final class TopicReplyItemLayout {
    public let context: any AccountContextProtocol
    let iconIdentity: ChatTopicIconIdentity
    public let message: Message
    public let text: TextViewLayout
    public let threadData: Message.AssociatedThreadInfo
    public let maxiumLines: Int32
    private let bgColor: NSColor
    private let textColor: NSColor
    public let isSideAccessory: Bool
    public init(context: any AccountContextProtocol, message: Message, isIncoming: Bool, isBubbled: Bool, threadData: Message.AssociatedThreadInfo, maxiumLines: Int32, isSideAccessory: Bool) {
        self.context = context
        self.iconIdentity = ChatTopicIconIdentity(account: context.account, fileId: threadData.icon, title: threadData.title, iconColor: threadData.iconColor, isGeneral: message.threadId == 1, generalColor: theme.chatList.badgeMutedBackgroundColor, customColor: theme.colors.accent)
        self.message = message
        self.threadData = threadData
        self.maxiumLines = maxiumLines
        if isSideAccessory {
            self.bgColor = theme.colors.background
            self.textColor = theme.colors.text
        } else {
            if isIncoming || !isBubbled {
                self.bgColor = theme.colors.accent.withAlphaComponent(0.2)
                self.textColor = theme.colors.accent
            } else {
                self.bgColor = theme.chat.grayText(false, true).withAlphaComponent(0.1)
                self.textColor = theme.chat.grayText(false, true)
            }
        }
        self.isSideAccessory = isSideAccessory
        let attr = NSMutableAttributedString()
        
        _ = attr.append(string: "\(clown) " + threadData.title, color: self.textColor, font: .normal(.text))
        
        let range = attr.string.nsstring.range(of: clown)
        if range.location != NSNotFound {
            let item: InlineStickerItem
            if let fileId = threadData.icon, fileId != 0 {
                item = .init(source: .attribute(.init(fileId: fileId, file: message.associatedMedia[MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)] as? TelegramMediaFile, emoji: "")))
            } else {
                let file = ChatInterfaceHooks.shared.makeTopicIconFile(threadData.title, threadData.iconColor, message.threadId == 1)
                item = .init(source: .attribute(.init(fileId: file.fileId.id, file: file, emoji: "")))
            }
            attr.addAttribute(TextInputAttributes.embedded, value: item, range: range)
        }
        
        self.text = .init(attr, maximumNumberOfLines: maxiumLines, alignment: .left, alwaysStaticItems: true)
    }
    
    public private(set) var size: NSSize = .zero
    
    public func measure(_ width: CGFloat) {
        
        text.measure(width: width)
        self.text.generateAutoBlock(backgroundColor: bgColor, minusHeight: 0, yInset: 1)
        self.size = NSMakeSize(text.layoutSize.width, text.layoutSize.height - 8)
        
    }
}

public final class TopicReplyItemView: Control {
    private let textLayer = TextViewLayer()
    private var iconIdentity: ChatTopicIconIdentity?
    private var inlineStickerItemViews: [InlineStickerItemLayer.Key: InlineStickerItemLayer] = [:]

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textLayer.anchorPoint = .zero
        textLayer.position = NSPoint(x: -2, y: -3)
        layer?.addSublayer(textLayer)
        scaleOnClick = true
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var accessibilityDefaultLabel: String? {
        let text = textLayer.textLayout?.attributedString.string
        return text?.isEmpty == false ? text : nil
    }

    public func update(item: TopicReplyItemLayout, animated: Bool) {
        if iconIdentity != item.iconIdentity {
            for icon in inlineStickerItemViews.values {
                icon.isPlayable = false
                icon.removeFromSuperlayer()
            }
            inlineStickerItemViews.removeAll(keepingCapacity: true)
            iconIdentity = item.iconIdentity
        }
        textLayer.update(item.text)
        let drawingBounds = CGRect(origin: .zero, size: textLayer.textSize).insetBy(dx: -2, dy: -3)
        if textLayer.bounds != drawingBounds { textLayer.bounds = drawingBounds }
        updateInlineStickers(context: item.context, textLayout: item.text)
        updateScale()
        updateAnimatableContent()
    }

    private func updateInlineStickers(context: any AccountContextProtocol, textLayout: TextViewLayout) {
        var validIds: [InlineStickerItemLayer.Key] = []
        var index = hashValue
        for item in textLayout.embeddedItems {
            if let stickerItem = item.value as? InlineStickerItem, case let .attribute(emoji) = stickerItem.source {
                let id = InlineStickerItemLayer.Key(id: emoji.fileId, index: index)
                validIds.append(id)
                let rect = item.rect.insetBy(dx: 2, dy: 2).offsetBy(dx: 6, dy: 2)
                let icon: InlineStickerItemLayer
                if let current = inlineStickerItemViews[id], current.frame.size == rect.size {
                    icon = current
                } else {
                    inlineStickerItemViews[id]?.isPlayable = false
                    inlineStickerItemViews[id]?.removeFromSuperlayer()
                    icon = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: emoji, size: rect.size, playPolicy: .playCount(2))
                    inlineStickerItemViews[id] = icon
                    icon.superview = self
                    textLayer.addSublayer(icon)
                }
                index += 1
                icon.frame = rect
            }
        }
        let obsolete = inlineStickerItemViews.keys.filter { !validIds.contains($0) }
        for key in obsolete {
            if let icon = inlineStickerItemViews.removeValue(forKey: key) {
                icon.isPlayable = false
                icon.removeFromSuperlayer()
            }
        }
    }

    public func updateAnimatableContent() {
        guard !inlineStickerItemViews.isEmpty else { return }
        let canPlay = window.map { !$0.canBecomeKey || $0.isKeyWindow } ?? false
        let textFrame = textLayer.frame.insetBy(dx: 2, dy: 3)
        let visibleText = visibleRect.intersection(textFrame)
        for icon in inlineStickerItemViews.values {
            let iconFrame = icon.frame.offsetBy(dx: textFrame.minX, dy: textFrame.minY)
            icon.isPlayable = canPlay && NSIntersectsRect(iconFrame, visibleText)
        }
    }

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        let origin = CGPoint(x: CGFloat(roundf(Float((frame.width - textLayer.textSize.width) / 2))), y: 0)
        let drawingBounds = CGRect(origin: .zero, size: textLayer.textSize).insetBy(dx: -2, dy: -3)
        let position = CGPoint(x: origin.x - 2, y: origin.y - 3)
        switch transition {
        case .immediate:
            if textLayer.bounds != drawingBounds { textLayer.bounds = drawingBounds }
            if textLayer.position != position { textLayer.position = position }
        case let .animated(duration, curve):
            if textLayer.bounds != drawingBounds {
                let previous = textLayer.presentation()?.bounds ?? textLayer.bounds
                textLayer.bounds = drawingBounds
                textLayer.animateBounds(from: previous, to: drawingBounds, duration: duration, timingFunction: curve.timingFunction)
            }
            if textLayer.position != position {
                let previous = textLayer.presentation()?.position ?? textLayer.position
                textLayer.position = position
                textLayer.animatePosition(from: previous, to: position, duration: duration, timingFunction: curve.timingFunction)
            }
        }
        updateScale()
        updateAnimatableContent()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScale()
        updateAnimatableContent()
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateAnimatableContent()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScale()
    }

    private func updateScale() {
        if textLayer.contentsScale != backingScaleFactor {
            textLayer.contentsScale = backingScaleFactor
            textLayer.setNeedsDisplay()
        }
    }
}
