import Cocoa
import TGUIKit
import TelegramContext
import InputView
import InlineStickerLayer

final class ChatLayerInlineEmoji {
    struct Visibility {
        fileprivate struct State {
            let hostLayer: CALayer
            let hostRect: CGRect
            let hostRegion: Region
            let anchor: CALayer
            let anchorRegion: Region?
        }
        fileprivate let state: State?
    }

    fileprivate struct Region {
        let clip: CGRect?
        let visible: CGRect
    }

    private enum Walk {
        case outside
        case hidden
        case region(Region)
    }

    private struct Entry {
        let occurrence: Int
        let source: ChatTextCustomEmojiAttribute
        let layer: InlineStickerItemLayer
    }

    let container = SimpleLayer()
    private var entries: [Entry] = []
    private weak var host: NSView?
    private weak var context: (any AccountContextProtocol)?
    private var accountId: ObjectIdentifier?
    private var bindingVersion: UInt64 = 0

    var isEmpty: Bool { entries.isEmpty }

    init() {
        container.anchorPoint = .zero
        container.masksToBounds = false
    }

    static func supports(_ layout: TextViewLayout) -> Bool {
        for item in layout.embeddedItems {
            guard let sticker = item.value as? InlineStickerItem,
                  case .attribute = sticker.source,
                  (sticker.playPolicy ?? .loop) == .loop,
                  item.rect.origin.x.isFinite, item.rect.origin.y.isFinite,
                  item.rect.width.isFinite, item.rect.height.isFinite,
                  item.rect.width >= 0, item.rect.height > 0 else { return false }
        }
        return true
    }

    @discardableResult
    func update(_ layout: TextViewLayout, context: any AccountContextProtocol, fallbackTextColor: NSColor, refreshVisibility: Bool = true) -> Bool {
        bindingVersion &+= 1
        let version = bindingVersion
        guard Self.supports(layout) else {
            reset()
            return false
        }
        let nextAccountId = ObjectIdentifier(context.account)
        if self.context !== context || accountId != nextAccountId {
            clearEntries()
            guard bindingVersion == version else { return false }
        }
        self.context = context
        accountId = nextAccountId
        let textColor: NSColor
        if layout.attributedString.length > 0 {
            textColor = layout.attributedString.attribute(.foregroundColor, at: layout.attributedString.length - 1, effectiveRange: nil) as? NSColor ?? fallbackTextColor
        } else {
            textColor = fallbackTextColor
        }
        container.bounds = CGRect(origin: .zero, size: layout.layoutSize)
        var nextIndex = 0
        for (occurrence, item) in layout.embeddedItems.enumerated() {
            guard item.rect.width > 10, let sticker = item.value as? InlineStickerItem,
                  case let .attribute(emoji) = sticker.source else { continue }
            let current: InlineStickerItemLayer
            if nextIndex < entries.count,
               entries[nextIndex].occurrence == occurrence,
               entries[nextIndex].source == emoji,
               entries[nextIndex].layer.size == item.rect.size,
               entries[nextIndex].layer.textColor == textColor,
               entries[nextIndex].layer.color == emoji.color {
                current = entries[nextIndex].layer
            } else {
                current = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: emoji, size: item.rect.size, playPolicy: .loop, textColor: textColor)
                guard bindingVersion == version else {
                    Self.remove(current)
                    return false
                }
                current.isPlayable = false
                let entry = Entry(occurrence: occurrence, source: emoji, layer: current)
                if nextIndex < entries.count {
                    Self.remove(entries[nextIndex].layer)
                    guard bindingVersion == version else {
                        Self.remove(current)
                        return false
                    }
                    entries[nextIndex] = entry
                } else {
                    entries.append(entry)
                }
            }
            if current.superview !== host { current.superview = host }
            if current.frame != item.rect { current.frame = item.rect }
            if (container.sublayers?.count ?? 0) <= nextIndex || container.sublayers?[nextIndex] !== current {
                container.insertSublayer(current, at: UInt32(nextIndex))
            }
            guard bindingVersion == version else { return false }
            nextIndex += 1
        }
        while entries.count > nextIndex {
            Self.remove(entries.removeLast().layer)
            guard bindingVersion == version else { return false }
        }
        if refreshVisibility { updateVisibility() }
        return bindingVersion == version
    }

    func attach(to parent: CALayer, host: NSView, refreshVisibility: Bool = true) {
        if self.host !== host { self.host = host }
        if container.superlayer !== parent { parent.addSublayer(container) }
        for entry in entries where entry.layer.superview !== host { entry.layer.superview = host }
        if refreshVisibility { updateVisibility() }
    }

    static func visibility(in host: NSView, anchor: CALayer? = nil) -> Visibility {
        guard host.window?.isKeyWindow == true, let region = visibleRegion(in: host),
              let hostRegion = ownRegion(region.layer, visibleRect: region.rect) else { return Visibility(state: nil) }
        var anchorLayer = region.layer
        var anchorRegion: Region? = hostRegion
        if let anchor, anchor !== region.layer {
            switch walk(from: anchor, to: region.layer, ancestorRegion: hostRegion, stop: nil) {
            case .outside:
                break
            case .hidden:
                anchorLayer = anchor
                anchorRegion = nil
            case let .region(value):
                anchorLayer = anchor
                anchorRegion = value
            }
        }
        return Visibility(state: .init(hostLayer: region.layer, hostRect: region.rect, hostRegion: hostRegion, anchor: anchorLayer, anchorRegion: anchorRegion))
    }

    func updateVisibility() {
        guard let host else {
            pause()
            return
        }
        updateVisibility(Self.visibility(in: host), from: host)
    }

    func updateVisibility(_ visibility: Visibility, from host: NSView) {
        guard self.host === host, let context else {
            pause()
            return
        }
        guard !entries.isEmpty else { return }
        guard let state = visibility.state, !context.isLite(.emoji) else {
            pause()
            return
        }
        var walk = Self.walk(from: container, to: state.anchor, ancestorRegion: state.anchorRegion, stop: state.hostLayer)
        if case .outside = walk, state.anchor !== state.hostLayer {
            walk = Self.walk(from: container, to: state.hostLayer, ancestorRegion: state.hostRegion, stop: nil)
        }
        guard case let .region(region) = walk else {
            pause()
            return
        }
        for index in entries.indices {
            let layer = entries[index].layer
            if layer.mask == nil, layer.superlayer === container, CATransform3DIsIdentity(layer.transform) {
                guard !layer.isHidden, layer.opacity > 0 else {
                    layer.isPlayable = false
                    continue
                }
                var rect = layer.frame
                if let clip = region.clip { rect = rect.intersection(clip) }
                layer.isPlayable = !rect.isNull && !rect.isEmpty && rect.intersects(region.visible)
            } else {
                layer.isPlayable = Self.isVisible(layer, hostLayer: state.hostLayer, visibleRect: state.hostRect)
            }
        }
    }

    private static func ownRegion(_ layer: CALayer, visibleRect: CGRect) -> Region? {
        guard !layer.isHidden, layer.opacity > 0 else { return nil }
        var clip: CGRect? = layer.masksToBounds ? layer.bounds : nil
        if let mask = layer.mask {
            guard !mask.isHidden, mask.opacity > 0 else { return nil }
            if !mask.frame.isEmpty { clip = clip.map { $0.intersection(mask.frame) } ?? mask.frame }
        }
        if let clip, clip.isNull || clip.isEmpty { return nil }
        return Region(clip: clip, visible: visibleRect)
    }

    private static func walk(from layer: CALayer, to ancestor: CALayer, ancestorRegion: Region?, stop: CALayer?) -> Walk {
        var current = layer
        var origin = CGPoint.zero
        var clip: CGRect?
        var translated = true
        while current !== ancestor {
            if current === stop { return .outside }
            guard !current.isHidden, current.opacity > 0 else { return .hidden }
            if translated, current.isGeometryFlipped || current.bounds.origin != .zero { translated = false }
            if current.masksToBounds {
                let rect = translated ? current.bounds.offsetBy(dx: origin.x, dy: origin.y) : layer.convert(current.bounds, from: current)
                clip = clip.map { $0.intersection(rect) } ?? rect
            }
            if let mask = current.mask {
                guard !mask.isHidden, mask.opacity > 0 else { return .hidden }
                if !mask.frame.isEmpty {
                    let rect = translated ? mask.frame.offsetBy(dx: origin.x, dy: origin.y) : layer.convert(mask.frame, from: current)
                    clip = clip.map { $0.intersection(rect) } ?? rect
                }
            }
            if let clip, clip.isNull || clip.isEmpty { return .hidden }
            guard let parent = current.superlayer else { return .outside }
            if translated, !CATransform3DIsIdentity(current.transform) || !CATransform3DIsIdentity(parent.sublayerTransform) { translated = false }
            if translated {
                let step = current.frame.origin
                origin.x -= step.x
                origin.y -= step.y
            }
            current = parent
        }
        guard let ancestorRegion else { return .hidden }
        if translated, ancestor.isGeometryFlipped || ancestor.bounds.origin != .zero { translated = false }
        let visible: CGRect
        let ancestorClip: CGRect?
        if translated {
            visible = ancestorRegion.visible.offsetBy(dx: origin.x, dy: origin.y)
            ancestorClip = ancestorRegion.clip?.offsetBy(dx: origin.x, dy: origin.y)
        } else {
            visible = layer.convert(ancestorRegion.visible, from: ancestor)
            ancestorClip = ancestorRegion.clip.map { layer.convert($0, from: ancestor) }
        }
        if let ancestorClip { clip = clip.map { $0.intersection(ancestorClip) } ?? ancestorClip }
        if let clip, clip.isNull || clip.isEmpty { return .hidden }
        return .region(Region(clip: clip, visible: visible))
    }

    func pause() {
        for entry in entries {
            entry.layer.isPlayable = false
        }
    }

    func reset() {
        bindingVersion &+= 1
        context = nil
        accountId = nil
        clearEntries()
    }

    func detach() {
        host = nil
        container.removeFromSuperlayer()
        reset()
    }

    private func clearEntries() {
        let removed = entries
        entries.removeAll()
        for entry in removed { Self.remove(entry.layer) }
    }

    private static func remove(_ layer: InlineStickerItemLayer) {
        layer.isPlayable = false
        layer.superview = nil
        layer.removeFromSuperlayer()
    }

    static func isVisible(_ layer: CALayer, in host: NSView) -> Bool {
        guard let region = visibleRegion(in: host) else { return false }
        return isVisible(layer, hostLayer: region.layer, visibleRect: region.rect)
    }

    private static func visibleRegion(in host: NSView) -> (layer: CALayer, rect: CGRect)? {
        guard host.window != nil, let layer = host.layer else { return nil }
        var ancestor: NSView? = host
        while let view = ancestor {
            guard !view.isHidden, view.alphaValue > 0 else { return nil }
            ancestor = view.superview
        }
        let rect = host.visibleRect
        return rect.isEmpty ? nil : (layer, rect)
    }

    private static func isVisible(_ layer: CALayer, hostLayer: CALayer, visibleRect: CGRect) -> Bool {
        var current = layer
        var visible = layer.bounds
        while true {
            guard !current.isHidden, current.opacity > 0 else { return false }
            if current.masksToBounds { visible = visible.intersection(current.bounds) }
            if let mask = current.mask {
                guard !mask.isHidden, mask.opacity > 0 else { return false }
                if !mask.frame.isEmpty { visible = visible.intersection(mask.frame) }
            }
            guard !visible.isNull, !visible.isEmpty else { return false }
            if current === hostLayer {
                return visible.intersects(visibleRect)
            }
            guard let parent = current.superlayer else { return false }
            visible = parent.convert(visible, from: current)
            current = parent
        }
    }

    deinit {
        clearEntries()
        container.removeFromSuperlayer()
    }
}
