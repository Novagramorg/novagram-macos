import Cocoa
import TGUIKit
import InputTextView

struct ChatLayerMessageTextPresentation {
    enum NativeFeature: Hashable {
        case streaming, quote, collapsed, embeddedItem, spoiler, formattedDate, blockBackground
    }

    final class Folding {
        let layout: FoldingTextLayout.ViewLayout
        init(_ layout: FoldingTextLayout.ViewLayout) { self.layout = layout }
    }

    struct Block {
        let layout: TextViewLayout
        let frame: NSRect
        let hasLinks: Bool
        let clipsTextToBounds: Bool
        let folding: Folding?
        var hasFormattedDates: Bool = false
    }

    let blocks: [Block]
    let size: NSSize
    let nativeFeatures: Set<NativeFeature>
    let requiresRevealAction: Bool
}

final class ChatLayerMessageTextNode: ChatLayerNode {
    private struct BlockId: Hashable {
        let parent: AnyHashable
        let index: Int
    }

    var revealBlockAtIndex: ((Int) -> Void)?
    private var messageId: AnyHashable?
    private var bindingVersion: UInt64 = 0
    private var hasAnimatedGeometry = false
    private(set) var textNodes: [ChatLayerTextNode] = []
    var selectableTextNodeIds: [AnyHashable] {
        return textNodes.compactMap { $0.isSelectable ? $0.id : nil }
    }

    func highlight(text: String, color: NSColor, range: NSRange? = nil, in layout: FoldingTextLayout) {
        guard textNodes.count == layout.blocks.count, zip(textNodes, layout.blocks).allSatisfy({ $0.textLayout === $1.text }) else { return }
        let string = layout.attributedString.string as NSString
        if let range, range.location >= 0, range.location != NSNotFound, range.length >= 0, range.location <= string.length, range.length <= string.length - range.location, string.substring(with: range) == text {
            var highlighted = false
            for (node, pair) in zip(textNodes, zip(layout.blocks, layout.blockRanges)) {
                let (block, blockRange) = pair
                if let intersection = blockRange.intersection(range) {
                    let localRange = NSRange(location: intersection.location - blockRange.location, length: intersection.length)
                    let localString = block.text.attributedString.string as NSString
                    guard localRange.location >= 0, localRange.location <= localString.length, localRange.length <= localString.length - localRange.location else { continue }
                    node.highlight(text: localString.substring(with: localRange), color: color, range: localRange)
                    highlighted = true
                }
            }
            if highlighted { return }
        }
        for node in textNodes {
            node.highlight(text: text, color: color)
        }
    }

    @discardableResult
    func update(_ presentation: ChatLayerMessageTextPresentation, messageId: AnyHashable, selectable: Bool) throws -> Bool {
        return try update(presentation, messageId: messageId, selectable: selectable, preservingSelectionGesture: false)
    }

    @discardableResult
    func update(_ presentation: ChatLayerMessageTextPresentation, messageId: AnyHashable, selectable: Bool, preservingSelectionGesture: Bool, transition: ContainedViewLayoutTransition = .immediate) throws -> Bool {
        bindingVersion &+= 1
        let version = bindingVersion
        if hasAnimatedGeometry && (!transition.isAnimated || self.messageId != messageId) {
            for node in textNodes { node.cancelMessageTransition() }
            hasAnimatedGeometry = false
        }
        let supported = presentation.nativeFeatures.isEmpty && (!presentation.requiresRevealAction || revealBlockAtIndex != nil)
        let blockCount = supported ? presentation.blocks.count : 0
        var nodes = textNodes
        if nodes.count > blockCount { nodes.removeSubrange(blockCount...) }
        while nodes.count < blockCount {
            nodes.append(ChatLayerTextNode(id: BlockId(parent: id, index: nodes.count), selectable: selectable))
        }
        let sameMessage = self.messageId == messageId
        let previousCount = textNodes.count
        let resetCount = !sameMessage || !selectable ? min(nodes.count, textNodes.count) : 0
        if nodes.count < textNodes.count {
            for node in textNodes.dropFirst(nodes.count) {
                node.resetInteraction()
                guard bindingVersion == version else { return false }
            }
        }
        try setChildren(nodes)
        guard bindingVersion == version else { return false }
        textNodes = nodes
        self.messageId = supported ? messageId : nil
        frame.size = supported ? presentation.size : .zero
        guard supported else { return false }
        hasAnimatedGeometry = hasAnimatedGeometry || (transition.isAnimated && sameMessage && previousCount > 0)
        for (index, pair) in zip(nodes, presentation.blocks).enumerated() {
            let (node, block) = pair
            if index < resetCount {
                node.resetInteraction()
                guard bindingVersion == version else { return false }
            }
            if node.isSelectable != selectable {
                node.isSelectable = selectable
                guard bindingVersion == version else { return false }
            }
            let blockTransition: ContainedViewLayoutTransition = sameMessage && index < previousCount ? transition : .immediate
            node.setQuoteClipping(block.clipsTextToBounds, rounded: block.folding != nil)
            node.updateFolding(block.folding?.layout, transition: blockTransition)
            if block.folding != nil {
                if node.onTextClick == nil {
                    node.onTextClick = { [weak self] in
                        guard let self, !self.textNodes.contains(where: { $0.textLayout?.selectedRange.hasSelectText == true }), let reveal = self.revealBlockAtIndex else { return false }
                        reveal(index)
                        return true
                    }
                    guard bindingVersion == version else { return false }
                }
            } else if node.onTextClick != nil {
                node.onTextClick = nil
                guard bindingVersion == version else { return false }
            }
            node.update(block.layout, knownHasLinks: block.hasLinks, knownHasFormattedDates: block.hasFormattedDates, frame: block.frame, preservingSelectionGesture: preservingSelectionGesture && resetCount == 0, transition: blockTransition)
            guard bindingVersion == version else { return false }
            if block.clipsTextToBounds || !node.children.isEmpty {
                try node.updateCodeHeaders()
                guard bindingVersion == version else { return false }
            }
        }
        return true
    }
}
