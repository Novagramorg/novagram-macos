import Cocoa
import TGUIKit
import TelegramContext
import InputView
import InlineStickerLayer
@testable import ChatLayerEngine

public final class BenchmarkFixtures {
    fileprivate struct Model {
        let body: ChatMessageItem
        let captions: ChatRowItem
    }
    fileprivate let context: BlockContext
    fileprivate let models: [Model]
    public let caption: Bool
    public let blockCount: Int
    public let expectedMediaCount: Int

    public init(account: Account, caption: Bool, blocks: Int) {
        self.caption = caption
        blockCount = blocks
        expectedMediaCount = blocks * 3
        let context = BlockContext()
        self.context = context
        context.account = account
        var models: [Model] = []
        for variant in 0..<5 {
            var texts: [TextViewLayout] = []
            let full = NSMutableAttributedString(string: "")
            var ranges: [NSRange] = []
            var captions: [ChatRowItem.RowCaption] = []
            for index in 0..<blocks {
                let prefix = variant == 2 ? "Edited \(index) " : "Message \(index) "
                let text = NSMutableAttributedString(string: prefix, attributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black])
                for occurrence in 0..<3 {
                    let source = Int64((index + occurrence) % 5 + 1 + (variant == 3 ? 20 : 0))
                    let emoji = ChatTextCustomEmojiAttribute(fileId: source, file: EmojiFile(revision: occurrence), color: occurrence == 1 ? .red : nil)
                    let range = NSRange(location: text.length, length: 2)
                    text.append(NSAttributedString(string: "🦆", attributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black]))
                    text.addAttribute(TextInputAttributes.embedded, value: InlineStickerItem(source: .attribute(emoji)), range: range)
                    text.addAttribute(TextInputAttributes.customEmoji, value: TextInputTextCustomEmojiAttribute(fileId: source), range: range)
                }
                text.append(NSAttributedString(string: " tail", attributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black]))
                let layout = TextViewLayout(text)
                texts.append(layout)
                ranges.append(NSRange(location: full.length, length: text.length))
                full.append(text)
                let captionLayout = FoldingTextLayout(attributedString: text, blocks: [layout], blockRanges: [NSRange(location: 0, length: text.length)], context: context, revealed: [])
                captionLayout.measure(width: 240)
                captions.append(ChatRowItem.RowCaption(messageId: index + 1, id: UInt32(index + 1), layout: captionLayout, offset: NSPoint(x: 7, y: CGFloat(index) * 42 + 13)))
            }
            if variant == 4 {
                captions.reverse()
                for (index, caption) in captions.enumerated() { caption.offset = NSPoint(x: 7, y: CGFloat(index) * 42 + 13) }
            }
            let bodyLayout = FoldingTextLayout(attributedString: full, blocks: texts, blockRanges: ranges, context: context, revealed: [])
            bodyLayout.measure(width: 240)
            let body = ChatMessageItem(id: 1, layout: bodyLayout)
            body.textOrigin = NSPoint(x: 7, y: 13)
            models.append(Model(body: body, captions: ChatRowItem(captions)))
        }
        self.models = models
    }
}

public final class BenchmarkDriver {
    public let root: NSView
    private let fixtures: BenchmarkFixtures
    private let body: LayerChatTextRow?
    private let captions: LayerCaptionRow?
    private var modelIndex = 0

    public init(fixtures: BenchmarkFixtures) {
        self.fixtures = fixtures
        let frame = CGRect(x: 0, y: 0, width: 320, height: max(300, CGFloat(fixtures.blockCount) * 48 + 30))
        if fixtures.caption {
            let row = LayerCaptionRow(frame: frame)
            captions = row
            body = nil
            root = row
        } else {
            let row = LayerChatTextRow(frame: frame)
            body = row
            captions = nil
            root = row
        }
    }

    public func bind(_ index: Int) {
        modelIndex = index
        if let body {
            body.bind(fixtures.models[index].body)
            body.finishLayout()
        } else if let captions {
            captions.bind(fixtures.models[index].captions)
            captions.finishLayout()
        }
    }

    private var hosts: [ChatLayerMessageTextView] {
        if let body { return body.layerText.map { [$0] } ?? [] }
        return captions?.captionViews.compactMap { $0.layerView } ?? []
    }

    private var nativeTexts: [TextView] {
        if let body { return body.text?.textViews ?? [] }
        return captions?.captionViews.flatMap { $0.nativeView?.textViews ?? [] } ?? []
    }

    public var rendersLayers: Bool {
        if fixtures.caption { return hosts.count == fixtures.blockCount }
        return hosts.count == 1
    }

    public var rendersNative: Bool {
        return hosts.isEmpty && nativeTexts.count == fixtures.blockCount
    }

    public var texts: [TextViewLayout] {
        if let body { return (body.item as? ChatMessageItem)?.textLayout.blocks.map { $0.text } ?? [] }
        return (captions?.item as? ChatRowItem)?.captionLayouts.flatMap { $0.layout.blocks.map { $0.text } } ?? []
    }

    public var media: [InlineStickerLayer.InlineStickerItemLayer] {
        var visited = Set<ObjectIdentifier>()
        func collect(_ layer: CALayer) -> [InlineStickerItemLayer] {
            guard visited.insert(ObjectIdentifier(layer)).inserted else { return [] }
            if let media = layer as? InlineStickerItemLayer { return [media] }
            return layer.sublayers?.flatMap(collect) ?? []
        }
        func visit(_ view: NSView) -> [InlineStickerItemLayer] {
            return (view.layer.map(collect) ?? []) + view.subviews.flatMap(visit)
        }
        return visit(root)
    }

    public func selectFirst(_ range: NSRange) {
        if let node = hosts.first?.body.textNodes.first {
            node.setExternalSelection(range)
        } else if let text = nativeTexts.first, let layout = text.textLayout {
            layout.selectedRange.range = range
            text.needsDisplay = true
        }
    }

    public func copyFirst() -> NSAttributedString? {
        var copied: NSAttributedString?
        if let node = hosts.first?.body.textNodes.first {
            node.copyText = { copied = $0 }
            _ = node.onCommand?(#selector(ChatLayerSceneView.copy(_:)))
            node.copyText = nil
        } else if let text = nativeTexts.first, let layout = text.textLayout {
            let previous = layout.interactions.copyAttributedString
            layout.interactions.copyAttributedString = { copied = $0; return true }
            text.copy(self)
            layout.interactions.copyAttributedString = previous
        }
        return copied
    }
}
