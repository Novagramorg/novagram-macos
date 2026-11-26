import Cocoa
import TGUIKit
import InputTextView
import InputView
import InlineStickerLayer

extension ChatLayerMessageTextPresentation {
    private enum AttributeKeys {
        static let quote = TextInputAttributes.quote.rawValue as NSString
        static let spoiler = TextInputAttributes.spoiler.rawValue as NSString
        static let customEmoji = TextInputAttributes.customEmoji.rawValue as NSString
        static let embedded = TextInputAttributes.embedded.rawValue as NSString
        static let formattedDate = TextInputAttributes.formattedDate.rawValue as NSString
        static let link = NSAttributedString.Key.link.rawValue as NSString
    }

    @inline(__always)
    private static func attribute(_ attributes: CFDictionary, _ key: NSString) -> UnsafeRawPointer? {
        return CFDictionaryGetValue(attributes, Unmanaged.passUnretained(key).toOpaque())
    }

    private static func supportsInlineEmoji(_ raw: UnsafeRawPointer, attributes: CFDictionary, measuredItems: Set<ObjectIdentifier>) -> Bool {
        guard let emoji = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? TextInputTextCustomEmojiAttribute,
              let embedded = Self.attribute(attributes, AttributeKeys.embedded),
              let sticker = Unmanaged<AnyObject>.fromOpaque(embedded).takeUnretainedValue() as? InlineStickerItem,
              case let .attribute(source) = sticker.source, source.fileId == emoji.fileId else { return false }
        return measuredItems.contains(ObjectIdentifier(sticker))
    }

    static func simpleText(_ layout: FoldingTextLayout) -> Self? {
        guard !layout.appendingAnimation, !layout.blocks.isEmpty else { return nil }
        var blocks: [Block] = []
        var y: CGFloat = 0
        var requiresRevealAction = false
        var hasInlineEmoji = false
        for block in layout.blocks {
            let text = block.text
            let canReveal = block.canReveal
            let inlineEmoji = !text.embeddedItems.isEmpty && ChatLayerInlineEmoji.supports(text)
            let measuredItems: Set<ObjectIdentifier> = inlineEmoji ? Set(text.embeddedItems.compactMap { ($0.value as? InlineStickerItem).map(ObjectIdentifier.init) }) : []
            hasInlineEmoji = hasInlineEmoji || inlineEmoji
            guard (block.isRevealed || canReveal), (text.embeddedItems.isEmpty || inlineEmoji),
                  !text.hasBlock, text.maskBlockImage.1 == nil else { return nil }
            let string = text.attributedString as CFAttributedString
            let length = CFAttributedStringGetLength(string)
            var hasLinks = false
            var hasFormattedDates = false
            var hasQuote = false
            var index = 0
            while index < length {
                var range = CFRange()
                let attributes = CFAttributedStringGetAttributes(string, index, &range)!
                guard Self.attribute(attributes, AttributeKeys.spoiler) == nil else { return nil }
                if let emoji = Self.attribute(attributes, AttributeKeys.customEmoji) {
                    guard inlineEmoji, Self.supportsInlineEmoji(emoji, attributes: attributes, measuredItems: measuredItems) else { return nil }
                }
                if let date = Self.attribute(attributes, AttributeKeys.formattedDate) {
                    guard Unmanaged<AnyObject>.fromOpaque(date).takeUnretainedValue() is TextViewFormattedDateData else { return nil }
                    hasFormattedDates = true
                }
                if let quote = Self.attribute(attributes, AttributeKeys.quote) {
                    guard Unmanaged<AnyObject>.fromOpaque(quote).takeUnretainedValue() is TextViewBlockQuoteData else { return nil }
                    hasQuote = true
                }
                if Self.attribute(attributes, AttributeKeys.link) != nil { hasLinks = true }
                index = range.location + range.length
            }
            if inlineEmoji && (!block.isRevealed || canReveal || hasQuote) { return nil }
            if blocks.isEmpty { blocks.reserveCapacity(layout.blocks.count) }
            let height = block.isRevealed ? block.layoutSize.height : block.size.height
            requiresRevealAction = requiresRevealAction || canReveal
            blocks.append(Block(layout: text, frame: NSRect(x: 0, y: y, width: block.layoutSize.width, height: height), hasLinks: hasLinks, clipsTextToBounds: hasQuote, folding: canReveal ? Folding(block) : nil, hasFormattedDates: hasFormattedDates))
            y += height
        }
        if hasInlineEmoji && requiresRevealAction { return nil }
        return Self(blocks: blocks, size: layout.size, nativeFeatures: [], requiresRevealAction: requiresRevealAction)
    }

    init(_ item: ChatMessageItem) {
        self.init(item.textLayout)
    }

    init(_ layout: FoldingTextLayout) {
        var blocks: [Block] = []
        blocks.reserveCapacity(layout.blocks.count)
        var features = Set<NativeFeature>()
        if layout.appendingAnimation { features.insert(.streaming) }
        var y: CGFloat = 0
        var requiresRevealAction = false
        var hasInlineEmoji = false
        for block in layout.blocks {
            let text = block.text
            let canReveal = block.canReveal
            requiresRevealAction = requiresRevealAction || canReveal
            let height = block.isRevealed ? block.layoutSize.height : block.size.height
            if !block.isRevealed && !canReveal { features.insert(.collapsed) }
            let inlineEmoji = !text.embeddedItems.isEmpty && ChatLayerInlineEmoji.supports(text)
            let measuredItems: Set<ObjectIdentifier> = inlineEmoji ? Set(text.embeddedItems.compactMap { ($0.value as? InlineStickerItem).map(ObjectIdentifier.init) }) : []
            hasInlineEmoji = hasInlineEmoji || inlineEmoji
            if !text.embeddedItems.isEmpty && !inlineEmoji { features.insert(.embeddedItem) }
            if text.hasBlock || text.maskBlockImage.1 != nil { features.insert(.blockBackground) }
            var hasLinks = false
            var hasFormattedDates = false
            var hasQuote = false
            let string = text.attributedString as CFAttributedString
            let length = CFAttributedStringGetLength(string)
            var index = 0
            while index < length {
                var range = CFRange()
                let attributes = CFAttributedStringGetAttributes(string, index, &range)!
                if let quote = Self.attribute(attributes, AttributeKeys.quote) {
                    hasQuote = Unmanaged<AnyObject>.fromOpaque(quote).takeUnretainedValue() is TextViewBlockQuoteData
                    if inlineEmoji { features.insert(.embeddedItem) }
                }
                if Self.attribute(attributes, AttributeKeys.spoiler) != nil { features.insert(.spoiler) }
                if let emoji = Self.attribute(attributes, AttributeKeys.customEmoji),
                   !inlineEmoji || !Self.supportsInlineEmoji(emoji, attributes: attributes, measuredItems: measuredItems) {
                    features.insert(.embeddedItem)
                }
                if let date = Self.attribute(attributes, AttributeKeys.formattedDate) {
                    if Unmanaged<AnyObject>.fromOpaque(date).takeUnretainedValue() is TextViewFormattedDateData { hasFormattedDates = true }
                    else { features.insert(.formattedDate) }
                }
                if Self.attribute(attributes, AttributeKeys.link) != nil { hasLinks = true }
                index = range.location + range.length
            }
            blocks.append(Block(layout: text, frame: NSRect(x: 0, y: y, width: block.layoutSize.width, height: height), hasLinks: hasLinks, clipsTextToBounds: hasQuote, folding: canReveal ? Folding(block) : nil, hasFormattedDates: hasFormattedDates))
            y += height
        }
        if hasInlineEmoji && (requiresRevealAction || blocks.contains(where: { !$0.layout.embeddedItems.isEmpty && $0.clipsTextToBounds })) { features.insert(.embeddedItem) }
        self.init(blocks: blocks, size: layout.size, nativeFeatures: features, requiresRevealAction: requiresRevealAction)
    }
}
