import Cocoa
import TGUIKit

import Postbox
import SwiftSignalKit
import AvatarUI
import TelegramContext
import TelegramTheme

private let duration: TimeInterval = 0.4
private let timingFunction: CAMediaTimingFunctionName = .spring

private func makeCommentsImageLayer() -> SimpleLayer {
    let layer = SimpleLayer()
    layer.anchorPoint = .zero
    layer.masksToBounds = true
    layer.edgeAntialiasingMask = []
    return layer
}

private func changeCommentsLayerPosition(_ layer: CALayer, to position: NSPoint, animated: Bool) {
    guard position != layer.frame.origin else { return }
    if animated {
        var from = layer.frame.origin
        if let presentation = layer.presentation(), layer.animation(forKey: "position") != nil {
            from = presentation.frame.origin
        }
        layer.animatePosition(from: from, to: position, duration: 0.2, timingFunction: .easeOut)
    } else {
        layer.removeAnimation(forKey: "position")
    }
    layer.frame.origin = position
}





public protocol ChannelCommentRenderer {
    func update(data: ChannelCommentsRenderData, size: NSSize, animated: Bool)
    var firstTextPosition: NSPoint { get }
    var lastTextPosition: NSPoint { get }
    var progressIndicatorPosition: NSPoint { get }
    var progressIndicatorSize: NSSize { get }
    var progressIndicatorColor: NSColor { get }
}


public class CommentsBasicControl : Button, ChannelCommentRenderer {
    
    fileprivate var textViews: [ChannelCommentsRenderData.Text : (ChatReactionTextLayer, ChannelCommentsRenderData.Text)] = [:]
    fileprivate var renderData: ChannelCommentsRenderData?
    fileprivate var size: NSSize = .zero
    fileprivate var progressView: ProgressIndicator?
    
    public var bubbleMode: Bool {
        return self.renderData?.bubbleMode ?? false
    }
    
    public func update(data: ChannelCommentsRenderData, size: NSSize, animated: Bool) {
        _ = lastTextPosition
        self.size = size
        self.renderData = data
        self.removeAllHandlers()
        
        self.set(handler: { [weak data] _ in
            data?.handler()
        }, for: .SingleClick)
        
        
        enum NumericAnimation {
            case forward
            case backward
        }
        
        var addition: [Int : NumericAnimation] = [:]
        var previousTextPos:[Int: NSPoint] = [:]
        for (key, textView) in textViews {
            let title = data._title.first(where: { $0.hashValue == key.hashValue })
            if textView.1 != title {
                let updated = title ?? key
                if let title = title {
                    addition[key.hashValue] = title < key ? .backward : .forward
                }
                
                textViews[key] = nil
                let field = textView.0
                previousTextPos[key.hashValue] = field.frame.origin
                if animated {
                    switch updated.animation {
                    case .crossFade:
                        field.animateAlpha(from: 1, to: 0, duration: duration, timingFunction: timingFunction, removeOnCompletion: false, completion: { [weak field] _ in
                            field?.removeFromSuperlayer()
                        })
                    case .numeric:
                        field.animateAlpha(from: 1, to: 0, duration: duration, timingFunction: timingFunction, removeOnCompletion: false, completion: { [weak field] _ in
                            field?.removeFromSuperlayer()
                        })
                        
                        let direction = addition[key.hashValue]
                        switch direction {
                        case .forward?:
                            field.animatePosition(from: field.frame.origin, to: NSMakePoint(field.frame.minX, field.frame.maxY), timingFunction: timingFunction, removeOnCompletion: false)
                        case .backward?:
                            field.animatePosition(from: field.frame.origin, to: NSMakePoint(field.frame.minX, field.frame.minY - field.frame.height), timingFunction: timingFunction, removeOnCompletion: false)
                        case .none:
                            break
                        }
                    }
                } else {
                    field.removeFromSuperlayer()
                }
            }
        }
        var pos = firstTextPosition
        for layout in data.titleLayout {
            if let view = textViews[layout.1] {
                if animated {
                    view.0.animatePosition(from: view.0.frame.origin - pos, to: .zero, timingFunction: timingFunction, removeOnCompletion: true, additive: true)
                }
                if view.0.frame.origin != pos { view.0.frame.origin = pos }
            } else {
                let current = ChatReactionTextLayer()
                current.frame = CGRect(origin: pos, size: layout.0.layoutSize)
                self.textViews[layout.1] = (current, layout.1)
                current.update(layout.0, in: self)
                if animated {
                    switch layout.1.animation {
                    case .crossFade:
                        current.animateAlpha(from: 0, to: 1, duration: duration)
                    case .numeric:
                        let direction = addition[layout.1.hashValue]
                        switch direction {
                        case .forward?:
                            current.animatePosition(from: NSMakePoint(pos.x, pos.y - layout.0.layoutSize.height), to: pos, timingFunction: timingFunction)
                        case .backward?:
                            current.animatePosition(from: NSMakePoint(pos.x, pos.y + layout.0.layoutSize.height), to: pos, timingFunction: timingFunction)
                        case .none:
                            break
                        }
                        
                        current.animateAlpha(from: 0, to: 1, duration: duration)
                    }
                }
            }
            pos.x += max(layout.0.layoutSize.width, 4)
        }
        
        if data.isLoading {
            if progressView == nil {
                let indicator = ProgressIndicator(frame: NSMakeRect(0, 0, progressIndicatorSize.width, progressIndicatorSize.height))
                self.progressView = indicator
                self.progressView?.progressColor = progressIndicatorColor
                addSubview(indicator)
                if animated {
                    indicator.layer?.animateAlpha(from: 0, to: 1, duration: duration,  timingFunction: timingFunction)
                }
            }
            self.progressView?.progressColor = progressIndicatorColor
        } else {
            if animated {
                if let progressView = self.progressView {
                    self.progressView = nil
                    progressView.layer?.animateAlpha(from: 1, to: 0, duration: duration, timingFunction: timingFunction, removeOnCompletion: false, completion: { [weak progressView] _ in
                        progressView?.removeFromSuperview()
                    })
                }
            } else {
                self.progressView?.removeFromSuperview()
                self.progressView = nil
            }
        }
        self.progressView?.setFrameOrigin(progressIndicatorPosition)
    }
    
    public var firstTextPosition: NSPoint {
        return .zero
    }

    public override var accessibilityDefaultLabel: String? {
        guard let renderData else { return nil }
        let label = renderData._title.map { $0.text.string }.joined()
        return label.isEmpty ? nil : label
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTextScale()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateTextScale()
    }

    private func updateTextScale() {
        let scale = backingScaleFactor
        for (layer, _) in textViews.values { layer.updateScale(scale) }
    }
    
    public var progressIndicatorSize: NSSize {
        return NSMakeSize(16, 16)
    }
    
    public var progressIndicatorPosition: NSPoint {
        var rect = focus(progressIndicatorSize)
        rect.origin.x = 0
        return rect.origin
    }
    
    public var progressIndicatorColor: NSColor {
        return theme.colors.accentIcon
    }
    
    public override func layout() {
        super.layout()
        progressView?.setFrameOrigin(progressIndicatorPosition)
    }
    
    public var lastTextPosition: NSPoint {
        guard let render = renderData, !render.titleLayout.isEmpty else {
            return .zero
        }
        
        return firstTextPosition + NSMakePoint(render.titleLayout.reduce(0, {
            $0 + max($1.0.layoutSize.width, 4)
        }), 0)
    }

}


public final class ChannelCommentsRenderData {
    
    public struct Text : Hashable, Comparable {
        public enum Animation : Equatable {
            case crossFade
            case numeric
        }
        public let text: NSAttributedString
        public let animation: Animation
        public let index: Int
        
        public init(text: NSAttributedString, animation: Animation, index: Int) {
            self.text = text
            self.animation = animation
            self.index = index
        }
        
        public static func <(lhs: Text, rhs: Text) -> Bool {
            let lhsInt: Int? = Int(lhs.text.string)
            let rhsInt: Int? = Int(rhs.text.string)
            
            if let lhsInt = lhsInt, let rhsInt = rhsInt {
                return lhsInt < rhsInt
            }
            return false
        }
        
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(index)
        }
    }
    
    public var titleSize: NSSize {
        return titleLayout.reduce(NSZeroSize, { current, value in
            var current = current
            current.width += max(value.0.layoutSize.width, 4)
            current.height = max(value.0.layoutSize.height, current.height)
            return current
        })
    }
    
    public let _title: [Text]
    public let peers:[Avatar]
    public var drawBorder: Bool
    public let context: any AccountContextProtocol
    public let message: Message?
    public let hasUnread: Bool
    public let isLoading: Bool
    public let bubbleMode: Bool
    fileprivate var titleLayout:[(TextViewLayout, Text)] = []
    fileprivate let handler: ()->Void
    
    public init(context: any AccountContextProtocol, message: Message?, hasUnread: Bool, title: [Text], peers: [Peer], drawBorder: Bool, isLoading: Bool, bubbleMode: Bool, handler: @escaping()->Void = {}) {
        self.context = context
        self.message = message
        self._title = title
        self.isLoading = isLoading
        self.bubbleMode = bubbleMode
        var index: Int = 0
        self.peers = peers.map { peer in
            let avatar = Avatar(peer: peer, index: index)
            index += 1
            return avatar
        }
        self.drawBorder = drawBorder
        self.hasUnread = hasUnread
        self.handler = handler
    }
    
    public func makeSize() {
        self.titleLayout = _title.map {
            return (TextViewLayout($0.text, maximumNumberOfLines: 1, truncationType: .end), $0)
        }
        var mw: CGFloat = 200
        for layout in self.titleLayout {
            layout.0.measure(width: mw)
            mw -= max(layout.0.layoutSize.width, 4) - 2
        }
    }
    
    public func size(_ bubbled: Bool, _ isOverlay: Bool = false) -> NSSize {
        var width: CGFloat = 0
        var height: CGFloat = 0
        if isOverlay {
            let iconSize = theme.chat_comments_overlay.backingSize
            if titleSize.width > 0 {
                width += titleSize.width
                width += 10
                width = max(width, 31)
                height = max(iconSize.height + titleSize.height + 16, width)
            } else {
                width = 31
                height = 31
            }
        } else if bubbled, titleSize.width > 0 {
            width += titleSize.width
            width += (6 * 4) + 13
            if peers.isEmpty {
                width += theme.icons.channel_comments_bubble.backingSize.width + 2
            } else {
                if peers.count == 1 {
                    width += 24
                } else {
                    width += 22 + (22 * CGFloat(peers.count - 1))
                }
            }
            width += theme.icons.channel_comments_bubble_next.backingSize.width
            height = ChatRowItem.channelCommentsBubbleHeight
            
            if hasUnread {
                width += 10
            }
        } else if titleSize.width > 0 {
            width += titleSize.width
            width += 3
            width += theme.icons.channel_comments_list.backingSize.width
            height = ChatRowItem.channelCommentsHeight
        }
        return NSMakeSize(width, height)
    }
}

public class ChannelCommentsBubbleControl: CommentsBasicControl {
    private var peers:[Avatar] = []
    private var avatars:[AvatarContentLayer] = []
    private let avatarsContainer = SimpleLayer(frame: NSMakeRect(0, 0, 22 * 3, 22))
    private let arrowView = makeCommentsImageLayer()
    private var dotView: SimpleLayer? = nil
    private var dotColor: NSColor?
        
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.addSublayer(avatarsContainer)
        let arrow = theme.icons.channel_comments_bubble_next
        arrowView.contents = arrow
        arrowView.frame = CGRect(origin: .zero, size: arrow.backingSize)
        self.layer?.addSublayer(arrowView)
    }

    
    public override var firstTextPosition: NSPoint {
        guard let render = renderData, !render.titleLayout.isEmpty else {
            return .zero
        }
        var rect: CGRect = .zero
        
        if render.peers.isEmpty {
            var f = focus(theme.icons.channel_comments_bubble.backingSize)
            if bubbleMode {
                f.origin.x = 18 + 6
            } else {
                f.origin.x = 5
            }
            rect = f
        } else {
            if render.peers.count == 1 {
                rect = focus(NSMakeSize(24 * CGFloat(render.peers.count), 22))
            } else {
                rect = focus(NSMakeSize(22 + (17 * CGFloat(render.peers.count - 1)), 22))
            }
            if bubbleMode {
                rect.origin.x = 18 + 6
            } else {
                rect.origin.x = 5
            }
        }
        
        var f = focus(render.titleSize)
        f.origin.x = rect.maxX + 6
        f.origin.y -= 1
        rect = f
        
        return rect.origin
    }
    
    public override var progressIndicatorPosition: NSPoint {
        var rect = focus(progressIndicatorSize)
        rect.origin.x = size.width - arrowView.frame.width - (bubbleMode ? 6 : 0)
        return rect.origin
    }
    
    public override var progressIndicatorColor: NSColor {
        return theme.colors.accentIcon
    }
    
    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        

        if let render = renderData {
            if render.drawBorder {
                ctx.setFillColor(theme.colors.accentIconBubble_incoming.withAlphaComponent(0.15).cgColor)
                ctx.fill(NSMakeRect(0, 0, frame.width, .borderSize))
            }
            if render.peers.isEmpty {
                var f = focus(theme.icons.channel_comments_bubble.backingSize)
                if bubbleMode {
                    f.origin.x = 13 + 6
                } else {
                    f.origin.x = 0
                }
                ctx.draw(theme.icons.channel_comments_bubble, in: f)
            }
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func update(data: ChannelCommentsRenderData, size: NSSize, animated: Bool) {
        let previousLastTextPosition = lastTextPosition
        
        super.update(data: data, size: size, animated: animated)
                
        CATransaction.begin()
        
        let (removed, inserted, updated) = mergeListsStableWithUpdates(leftList: self.peers, rightList: data.peers)
        
        for removed in removed.reversed() {
            let control = avatars.remove(at: removed)
            let peer = self.peers[removed]
            let haveNext = data.peers.contains(where: { $0.stableId == peer.stableId })
            control.updateLayout(size: NSMakeSize(22, 22), isClipped: false, animated: animated)
            control.anchorPoint = NSMakePoint(0.5, 0.5)
            if animated && !haveNext {
                control.animateAlpha(from: 1, to: 0, duration: duration, timingFunction: timingFunction, removeOnCompletion: false, completion: { [weak control] _ in
                    control?.removeFromSuperlayer()
                })
                control.animateScaleSpring(from: 1.0, to: 0.2, duration: duration, center: false )
            } else {
                control.removeFromSuperlayer()
            }
        }
        let imageSize = NSMakeSize(22, 22)
        for inserted in inserted {
            let control = AvatarContentLayer(context: data.context, peer: inserted.1.peer, message: data.message, synchronousLoad: false, size: imageSize)
            control.updateLayout(size: imageSize, isClipped: inserted.0 != 0, animated: animated)
            control.frame = CGRect(origin: NSMakePoint(CGFloat(inserted.0) * 18, 0), size: imageSize)
            avatars.insert(control, at: inserted.0)
            if let _ = avatarsContainer.sublayers {
                avatarsContainer.sublayers?.insert(control, at: inserted.0)
            } else {
                avatarsContainer.addSublayer(control)
            }
            if animated {
                if let index = inserted.2 {
                    control.animatePosition(from: NSMakePoint(CGFloat(index) * 18, 0).offsetBy(dx: imageSize.width/2, dy: imageSize.height/2), to: control.frame.origin.offsetBy(dx: imageSize.width/2, dy: imageSize.height/2), timingFunction: timingFunction)
                } else {
                    control.animateAlpha(from: 0, to: 1, duration: duration, timingFunction: timingFunction)
                    control.animateScaleSpring(from: 0.2, to: 1.0, duration: duration, center: false)
                }
            }
        }
        for updated in updated {
            let control = avatars[updated.0]
            control.updateLayout(size: imageSize, isClipped: updated.0 != 0, animated: animated)
            let updatedPoint = NSMakePoint(CGFloat(updated.0) * 18, 0)
            if animated {
                control.animatePosition(from: control.frame.origin - updatedPoint, to: .zero, duration: duration, timingFunction: timingFunction, additive: true)
            }
            control.frame = CGRect(origin: updatedPoint, size: imageSize)
        }
        var index: CGFloat = 10
        if let sublayers = avatarsContainer.sublayers {
            for control in sublayers.compactMap({ $0 as? AvatarContentLayer }) {
                control.zPosition = index
                index -= 1
            }
        }
        
        
        self.peers = data.peers
        
        CATransaction.commit()

        enum NumericAnimation {
            case forward
            case backward
        }
                
        arrowView.isHidden = data.isLoading || !data.bubbleMode
        
        if animated {
            var f = size.bounds.focus(arrowView.frame.size)
            f.origin.x = size.width - 6 - f.width
            arrowView.animatePosition(from: arrowView.frame.origin - f.origin, to: .zero, timingFunction: timingFunction, additive: true)
        }
        
        
        if data.hasUnread {
            let size = NSMakeSize(6, 6)
            var f = focus(size)
            f.origin.x = lastTextPosition.x + 6
            f.origin.y += 1
            if self.dotView == nil {
                let effectivePos = previousLastTextPosition != .zero ? previousLastTextPosition : f.origin
                let dot = SimpleLayer()
                dot.anchorPoint = .zero
                dot.masksToBounds = true
                dot.isOpaque = true
                dot.edgeAntialiasingMask = []
                if #available(macOS 10.15, *) { dot.cornerCurve = .continuous }
                dot.frame = CGRect(origin: effectivePos, size: f.size)
                dot.cornerRadius = size.height / 2
                self.dotView = dot
                self.layer?.addSublayer(dot)
                if animated {
                    dot.animateAlpha(from: 0, to: 1, duration: duration, timingFunction: timingFunction)
                    dot.animateScaleSpring(from: 0.2, to: 1.0, duration: duration, bounce: true)
                }
            }
            guard let dotView = self.dotView else {
                return
            }
            if animated {
                dotView.animatePosition(from: dotView.frame.origin - f.origin, to: .zero, timingFunction: timingFunction, additive: true)
            }
            let color = theme.colors.accentIcon
            if dotColor != color || dotView.backgroundColor == nil {
                dotColor = color
                dotView.backgroundColor = color.cgColor
            }
        } else {
            if let dotView = dotView {
                self.dotView = nil
                self.dotColor = nil
                if animated {
                    dotView.animateAlpha(from: 1, to: 0, duration: duration, timingFunction: timingFunction, removeOnCompletion: false, completion: { [weak dotView] _ in
                        dotView?.removeFromSuperlayer()
                    })
                    dotView.animateScaleSpring(from: 1, to: 0.2, duration: duration)
                } else {
                    dotView.removeFromSuperlayer()
                }
            }
        }
        
        needsDisplay = true
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        var rect = focus(self.avatarsContainer.frame.size)
        if bubbleMode {
            rect.origin.x = 13 + 6
        } else {
            rect.origin.x = 0
        }
        if self.avatarsContainer.frame != rect { self.avatarsContainer.frame = rect }
        let arrowOrigin = NSMakePoint(frame.width - arrowView.frame.width - (bubbleMode ? 6 : 0), round((frame.height - arrowView.frame.height) / 2))
        if arrowView.frame.origin != arrowOrigin { arrowView.frame.origin = arrowOrigin }
        if let dotView {
            let dotOrigin = NSMakePoint(lastTextPosition.x + 6, round((frame.height - dotView.frame.height) / 2) + 1)
            if dotView.frame.origin != dotOrigin { dotView.frame.origin = dotOrigin }
        }
    }
    
}





public final class ChannelCommentsSmallControl : CommentsBasicControl {

    private let imageView = makeCommentsImageLayer()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.addSublayer(imageView)
    }

    public override var firstTextPosition: NSPoint {
        guard let render = renderData, !render.titleLayout.isEmpty else {
            return .zero
        }
        let size = theme.chat_comments_overlay.backingSize
        var iconFrame = focus(size)
        iconFrame.origin.y = 5
        
        var titleFrame = focus(render.titleSize)
        titleFrame.origin.y = iconFrame.maxY + 2
        return titleFrame.origin
    }
    
    public var imagePosition: NSPoint {
        if let renderData = renderData {
            let size = theme.chat_comments_overlay.backingSize
            if !renderData.titleLayout.isEmpty {
                var iconFrame = focus(size)
                iconFrame.origin.y = 5
                return iconFrame.origin
            } else {
                return focus(size).origin
            }
        }
        return .zero
    }
    
    public override var progressIndicatorPosition: NSPoint {
        return imagePosition
    }
    
    public override var progressIndicatorSize: NSSize {
        return theme.chat_comments_overlay.backingSize
    }
    
    public override var progressIndicatorColor: NSColor {
        if theme.bubbled && theme.backgroundMode.hasWallpaper {
            return theme.chatServiceItemTextColor
        } else {
            return theme.colors.accent
        }
    }
    
    public override func update(data: ChannelCommentsRenderData, size: NSSize, animated: Bool) {
        
        super.update(data: data, size: size, animated: animated)
        
        imageView.isHidden = data.isLoading
        
        
        let icon = theme.bubbled && theme.backgroundMode.hasWallpaper ? theme.chat_comments_overlay : theme.icons.channel_comments_overlay
        imageView.contents = icon
        imageView.frame.size = icon.backingSize
        
        layer?.cornerRadius = min(size.height, size.width) / 2
        
        let rect = CGRect(origin: .zero, size: size)
        let iconSize = theme.chat_comments_overlay.backingSize
        let iconPosition: NSPoint
        if !data.titleLayout.isEmpty {
            var iconFrame = rect.focus(iconSize)
            iconFrame.origin.y = 5
            iconPosition = iconFrame.origin
        } else {
            iconPosition = rect.focus(iconSize).origin
        }
        
        changeCommentsLayerPosition(imageView, to: iconPosition, animated: animated)
        change(size: size, animated: animated)
        needsDisplay = true
    }
    
    public override func layout() {
        super.layout()
        let origin = imagePosition
        if imageView.frame.origin != origin { imageView.frame.origin = origin }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
