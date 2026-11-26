import Foundation
import AppKit
import TGUIKit
import Localization

private func addHeartbeatAnimation(to layer: CALayer) {
    guard layer.animation(forKey: "heartbeatAnimation") == nil else {
        return
    }
    // Create a keyframe animation for the 'transform.scale' key path
    let animation = makeSpringAnimation("transform.scale")
    
    // Define the scale values for each keyframe (normal -> larger -> normal -> slightly larger -> normal)
    animation.fromValue = NSNumber(value: 0.4)
    animation.toValue = NSNumber(value: 1.35)
    animation.duration = 1.3
    
    animation.fillMode = .forwards
    
    // Repeat the animation indefinitely
    animation.repeatCount = Float.infinity
    animation.autoreverses = true
    
    
    // Add the animation to your layer
    layer.add(animation, forKey: "heartbeatAnimation")
}

enum PeerCallActionType : Int32 {
    case end = 100
    case redial = 99
    case accept = 98
    case mute = 97
    case screencast = 96
    case video = 95
    
    var title: String {
        switch self {
        case .end:
            return L10n.callEnd
        case .redial:
            return L10n.callRecall
        case .accept:
            return L10n.callAccept
        case .mute:
            return L10n.callMute
        case .screencast:
            return L10n.callScreen
        case .video:
            return L10n.callVideo
        }
    }
    
    var resource: ImageResource {
        switch self {
        case .end:
            return .icDecline
        case .redial:
            return .icRedial
        case .accept:
            return .icAccept
        case .mute:
            return .icMute
        case .screencast:
            return .icScreen
        case .video:
            return .icVideo
        }
    }
}

struct PeerCallAction : Comparable, Identifiable {
    static func < (lhs: PeerCallAction, rhs: PeerCallAction) -> Bool {
        return lhs.stableId.rawValue < rhs.stableId.rawValue
    }
    
    static func == (lhs: PeerCallAction, rhs: PeerCallAction) -> Bool {
        return lhs.stableId == rhs.stableId && lhs.enabled == rhs.enabled && lhs.active == rhs.active && lhs.interactive == rhs.interactive && lhs.loading == rhs.loading && lhs.attract == rhs.attract
    }
    
    
    let stableId: PeerCallActionType
    
    var text: String?
    
    var normal: CGImage
    var activeImage: CGImage?
    var image: CGImage? {
        if active, interactive {
            return activeImage
        } else {
            return normal
        }
    }
    
    var active: Bool = false
    var loading: Bool = false
    var enabled: Bool = true
    var interactive: Bool = true
    var attract: Bool = false
    var action:()->Void
}

private let actionSize = NSMakeSize(50, 50)


func makeNormalAction(_ image: NSImage) -> CGImage {
    let img = image._cgImage!
    return generateImage(actionSize, contextGenerator: { size, ctx in
        ctx.clear(size.bounds)
        ctx.round(size, size.height / 2)
        ctx.draw(img, in: size.bounds.focus(img.systemSize))
    }, scale: System.backingScale)!
}



func makeActiveAction(_ image: NSImage) -> CGImage {
    let img = image._cgImage!
    return generateImage(actionSize, contextGenerator: { size, ctx in
        ctx.clear(size.bounds)
        ctx.round(size, size.height / 2)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: size.bounds)
        
        ctx.clip(to: size.bounds.focus(img.systemSize), mask: img)
        
        ctx.setBlendMode(.clear)
        ctx.fill(size.bounds)
    }, scale: System.backingScale)!
}

private struct ActionImageKey: Hashable {
    let type: PeerCallActionType
    let interactive: Bool
    let scale: CGFloat
}

private var actionImageCache: [ActionImageKey: (normal: CGImage, active: CGImage?)] = [:]

private func actionImages(type: PeerCallActionType, resource: ImageResource, interactive: Bool) -> (normal: CGImage, active: CGImage?) {
    let key = ActionImageKey(type: type, interactive: interactive, scale: System.backingScale)
    if let cached = actionImageCache[key] {
        return cached
    }
    let image = NSImage(resource: resource)
    let images: (normal: CGImage, active: CGImage?) = (!interactive ? image._cgImage! : makeNormalAction(image), !interactive ? nil : makeActiveAction(image))
    actionImageCache[key] = images
    return images
}

func makeAction(type: PeerCallActionType, text: String, resource: ImageResource, active: Bool = false, enabled: Bool = true, loading: Bool = false, interactive: Bool = true, attract: Bool = false, action: @escaping()->Void) -> PeerCallAction {
    let images = actionImages(type: type, resource: resource, interactive: interactive)
    return .init(stableId: type, text: text, normal: images.normal, activeImage: images.active, active: active, loading: loading, enabled: enabled, interactive: interactive, attract: attract, action: action)
}


final class PeerCallActionView : Control {
    private let imageLayer: SimpleLayer = SimpleLayer(frame: actionSize.bounds)
    private let backgroundLayer: SimpleLayer = SimpleLayer(frame: actionSize.bounds)
    private let backgroundView = NSVisualEffectView(frame: actionSize.bounds)
    private var textView: TextView?
    
    private var attractAttention: SimpleLayer?
    
    private var progressView: InfiniteProgressView?
    
    private var isLoading: Bool = false
    
    private var state: PeerCallAction?
    
    override init() {
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: actionSize.width, height: actionSize.height + 5 + 15)))

        imageLayer.contentsGravity = .resizeAspectFill
        backgroundLayer.contentsGravity = .resizeAspectFill


        
        backgroundView.wantsLayer = true
        backgroundView.material = .light
        backgroundView.state = .active
        backgroundView.blendingMode = .withinWindow
        
        backgroundView.layer?.addSublayer(backgroundLayer)
        
        
        if #available(macOS 10.15, *) {
            backgroundLayer.cornerCurve = .continuous
            imageLayer.cornerCurve = .continuous
        }

        
        imageLayer.cornerRadius = imageLayer.frame.height / 2
        backgroundLayer.cornerRadius = imageLayer.frame.height / 2
        backgroundView.layer?.cornerRadius = backgroundView.frame.height / 2
        
        addSubview(backgroundView)
        
        layer?.masksToBounds = false
        scaleOnClick = true
        
        set(handler: { [weak self] _ in
            if let state = self?.state {
                state.action()
            }
        }, for: .Click)
        
    }
    
    func updateLoading(_ isLoading: Bool, animated: Bool) {
        self.isLoading = isLoading
        if isLoading {
            let current: InfiniteProgressView
            if let view = progressView {
                current = view
            } else {
                current = InfiniteProgressView(color: NSColor.random, lineWidth: 2)
                self.progressView = current
                backgroundView.addSubview(current)
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.4)
                }
            }
            current.frame = backgroundView.bounds.insetBy(dx: 1, dy: 1)
        } else if let view = progressView {
            performSubviewRemoval(view, animated: animated)
            self.progressView = nil
        }
    }
    
    override var isEnabled: Bool {
        get {
            return super.isEnabled && !isLoading
        }
        set {
            super.isEnabled = newValue
        }
    }
    
    override var mouseDownCanMoveWindow: Bool {
        return false
    }

    
    func updateEnabled(_ enabled: Bool, animated: Bool) {
        self.isEnabled = enabled
        
        change(opacity: enabled ? 1 : 0.7, animated: animated)
    }
    
    func updateAttraction(_ attract: Bool, animated: Bool) {
        if attract {
            let current: SimpleLayer
            if let layer = self.attractAttention {
                current = layer
            } else {
                current = SimpleLayer()
                current.frame = imageLayer.frame.insetBy(dx: 3, dy: 3)
                current.cornerRadius = current.frame.height / 2
                self.layer?.insertSublayer(current, at: 0)
                self.attractAttention = current
            }
            current.backgroundColor = NSColor.greenUI.withAlphaComponent(0.45).cgColor
            addHeartbeatAnimation(to: current)
        } else if let layer = self.attractAttention {
            performSublayerRemoval(layer, animated: animated)
            self.attractAttention = nil
        }
    }
    
    var size: NSSize {
        return backgroundView.frame.size
    }

    var accessibilityDeclines: Bool = false

    override var accessibilityDefaultLabel: String? {
        guard let state = self.state else {
            return nil
        }
        switch state.stableId {
        case .mute:
            return state.active ? strings().voiceOverCommonUnmute : strings().voiceOverCommonMute
        case .video:
            return strings().voiceOverCommonCamera
        case .screencast:
            return strings().voiceOverCommonShareScreen
        case .accept:
            return strings().voiceOverCommonAccept
        case .end:
            return accessibilityDeclines ? strings().voiceOverCommonDecline : strings().voiceOverCommonEndCall
        case .redial:
            return state.stableId.title
        }
    }

    override func accessibilityValue() -> Any? {
        guard let state = self.state else {
            return nil
        }
        switch state.stableId {
        case .video, .screencast:
            return state.active ? strings().voiceOverCommonOn : strings().voiceOverCommonOff
        default:
            return nil
        }
    }
    
    func update(_ data: PeerCallAction, animated: Bool) {
        
        let previousData = self.state
        self.state = data
        
        if let text = data.text {
            let current: TextView
            if let textView = self.textView {
                current = textView
            } else {
                current = TextView()
                self.textView = current
                current.isSelectable = false
                current.userInteractionEnabled = false
                current.isEventLess = true
                current.isAccessibilityDecorative = true
                addSubview(current)
            }
            if current.textLayout?.attributedString.string != text {
                let layout = TextViewLayout(.initialize(string: text, color: .white, font: .roundTimer(12)), maximumNumberOfLines: 1)
                layout.measure(width: 100)
                current.update(layout)
            }
        } else if let textView = self.textView {
            performSubviewRemoval(textView, animated: animated)
            self.textView = nil
        }
        
        self.imageLayer.contents = data.image
        
        if data.active && data.activeImage != nil {
            backgroundView.layer?.mask = self.imageLayer
        } else {
            backgroundView.layer?.mask = nil
        }
        
        if previousData?.active != data.active || previousData == nil {
            backgroundLayer.contents = data.image
            if animated {
                backgroundLayer.animateContents()
            }
        }
               
        updateAttraction(data.attract, animated: animated)
        updateLoading(data.loading, animated: animated)
        updateEnabled(data.enabled, animated: animated)
    }
    
    override func layout() {
        super.layout()
        self.updateLayout(size: frame.size, transition: .immediate)
    }
    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: backgroundView, frame: backgroundView.centerFrameX(y: 0))
        
        if let textView {
            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: backgroundView.frame.maxY + 5))
        }
    }

    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}
