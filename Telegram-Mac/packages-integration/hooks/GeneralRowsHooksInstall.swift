import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import InlineStickerLayer

private final class AppInlineTextRenderer: InlineTextRenderer {
    private var inlineStickerItemViews: [InlineStickerItemLayer.Key: SimpleLayer] = [:]

    func update(textView: TextView, layout: TextViewLayout, context: any AccountContextProtocol, insetEmoji: CGFloat, emojiOffset: NSPoint, decreaseAvatar: CGFloat) {
        guard let context = context as? AccountContext else {
            return
        }
        var validIds = InlineStickerKeyCollection()
        var index: Int = textView.hashValue

        let textColor: NSColor
        if layout.attributedString.length > 0 {
            var range: NSRange = NSMakeRange(NSNotFound, 0)
            let attrs = layout.attributedString.attributes(at: max(0, layout.attributedString.length - 1), effectiveRange: &range)
            textColor = attrs[.foregroundColor] as? NSColor ?? theme.colors.text
        } else {
            textColor = theme.colors.text
        }

        for item in layout.embeddedItems {
            if let stickerItem = item.value as? InlineStickerItem, item.rect.width > 10 {
                if case let .attribute(emoji) = stickerItem.source {

                    let id = InlineStickerItemLayer.Key(id: emoji.fileId, index: index, color: emoji.color ?? textColor)
                    validIds.append(id)

                    let rect = item.rect.insetBy(dx: insetEmoji, dy: insetEmoji).offsetBy(dx: emojiOffset.x, dy: emojiOffset.y)

                    let view: InlineStickerItemLayer
                    if let current = inlineStickerItemViews[id] as? InlineStickerItemLayer, current.frame.size == rect.size && current.textColor == id.color {
                        view = current
                    } else {
                        inlineStickerItemViews[id]?.removeFromSuperlayer()
                        view = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: emoji, size: rect.size, playPolicy: stickerItem.playPolicy ?? .loop, textColor: textColor)
                        inlineStickerItemViews[id] = view
                        view.superview = textView
                        textView.addEmbeddedLayer(view)
                    }
                    index += 1

                    view.frame = rect
                } else if case let .avatar(peer) = stickerItem.source {
                    let id = InlineStickerItemLayer.Key(id: peer.id.toInt64(), index: index)
                    validIds.append(id)
                    let rect = NSMakeRect(item.rect.minX, item.rect.minY + 3, item.rect.width - 3 - decreaseAvatar, item.rect.width - 3 - decreaseAvatar).offsetBy(dx: emojiOffset.x, dy: emojiOffset.y)

                    let view: InlineAvatarLayer
                    if let current = inlineStickerItemViews[id] as? InlineAvatarLayer {
                        view = current
                    } else {
                        inlineStickerItemViews[id]?.removeFromSuperlayer()
                        view = InlineAvatarLayer(context: context, frame: rect, peer: peer)
                        inlineStickerItemViews[id] = view
                        textView.addEmbeddedLayer(view)
                    }
                    index += 1
                    view.frame = rect
                }
            }
        }

        var removeKeys: [InlineStickerItemLayer.Key] = []
        for (key, itemLayer) in inlineStickerItemViews {
            if !validIds.contains(key) {
                removeKeys.append(key)
                itemLayer.removeFromSuperlayer()
            }
        }
        for key in removeKeys {
            inlineStickerItemViews.removeValue(forKey: key)
        }
    }

    func clear() {
        for (_, itemLayer) in inlineStickerItemViews {
            itemLayer.removeFromSuperlayer()
        }
        inlineStickerItemViews.removeAll()
    }

    func updateAnimatableContent(window: NSWindow?, isLite: Bool) {
        updateInlineStickerPlayback(inlineStickerItemViews.values, window: window, isLite: isLite)
    }
}

extension MediaAnimatedStickerView: @retroactive GeneralRowsAnimatedItemView {
    public func updateAnimatedItem(context: any AccountContextProtocol, file: TelegramMediaFile, size: NSSize, animated: Bool) {
        guard let context = context as? AccountContext else {
            return
        }
        self.update(with: file, size: size, context: context, parent: nil, table: nil, parameters: ChatAnimatedStickerMediaLayoutParameters(playPolicy: .loop, media: file), animated: animated, positionFlags: nil, approximateSynchronousValue: true)
    }
    public func updateStickerHeader(with media: Media, size: NSSize, context: any AccountContextProtocol, parent: Message?, table: TableView?, parameters: GeneralRowsStickerParameters?, animated: Bool, positionFlags: LayoutPositionFlags?, approximateSynchronousValue: Bool) {
        self.update(with: media, size: size, context: context, parent: parent, table: table, parameters: parameters as? ChatAnimatedStickerMediaLayoutParameters, animated: animated, positionFlags: positionFlags, approximateSynchronousValue: approximateSynchronousValue)
    }
}

extension ChatAnimatedStickerMediaLayoutParameters: @retroactive GeneralRowsStickerParameters {

}

func installGeneralRowsHooks() {
    GeneralRowsHooks.install(GeneralRowsHooks(linkExecutor: {
        return globalLinkExecutor
    }, linkAttribute: { contents, handler in
        return (NSAttributedString.Key.link.rawValue, inAppLink.callback(contents, handler))
    }, detectLinks: { attributedString in
        attributedString.detectLinks(type: [.Links], context: nil, openInfo: { _, _, _, _ in }, hashtag: nil, command: nil, applyProxy: nil, dotInMention: false)
    }, checkSelectedImage: { foregroundColor, backgroundColor in
        return generateCheckSelected(foregroundColor: foregroundColor, backgroundColor: backgroundColor)
    }, makeInlineTextRenderer: {
        return AppInlineTextRenderer()
    }, makeAnimatedItemView: {
        return MediaAnimatedStickerView(frame: .zero)
    }, makeStickerHeaderView: { frame in
        return MediaAnimatedStickerView(frame: frame)
    }, localStickerParameters: { sticker in
        return sticker.parameters
    }))
}
