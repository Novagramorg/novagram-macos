import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif

public enum ChatActivityAnimation {
    case none
    case text
    case uploading
    case recording
    case choosingSticker
}



final class ChatActivityIndicatorLayer: SimpleLayer {
    private struct Shape {
        let layer: CAShapeLayer
        let path: (CGFloat) -> CGPath
        let opacity: ((CGFloat) -> CGFloat)?
    }
    
    private var shapes: [Shape] = []
    private(set) var frameCount: Int = 0
    private(set) var loopDuration: Double = 0
    
    static func size(for type: ChatActivityAnimation) -> NSSize {
        switch type {
        case .choosingSticker:
            return choosingStickerActivitySize
        default:
            return NSMakeSize(26, 20)
        }
    }
    
    private func shapeLayer(fill: NSColor?, stroke: NSColor?, lineWidth: CGFloat = 1) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.contentsScale = System.backingScale
        layer.fillColor = fill?.cgColor
        layer.strokeColor = stroke?.cgColor
        layer.lineWidth = lineWidth
        layer.actions = ["path": NSNull(), "opacity": NSNull()]
        return layer
    }
    
    private func ellipse(_ rect: CGRect) -> CGPath {
        return CGPath(ellipseIn: rect, transform: nil)
    }
    
    private func roundedRect(_ rect: CGRect) -> CGPath {
        return CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
    }
    
    func configure(_ type: ChatActivityAnimation, theme: ActivitiesTheme) {
        self.sublayers?.forEach { $0.removeFromSuperlayer() }
        self.shapes = []
        let color = theme.textColor
        switch type {
        case .recording:
            self.frameCount = 42
            self.loopDuration = 0.7
            for index in 0 ..< 3 {
                let layer = shapeLayer(fill: nil, stroke: NSColor(rgb: color.rgb), lineWidth: 3)
                layer.lineCap = .round
                self.shapes.append(Shape(layer: layer, path: { value in
                    let path = CGMutablePath()
                    path.addArc(center: recordingActivityArcCenter, radius: recordingArcsFrame(value)[index].radius, startAngle: -recordingActivityArcAngle, endAngle: recordingActivityArcAngle, clockwise: false)
                    return path
                }, opacity: { value in
                    return recordingArcsFrame(value)[index].alpha
                }))
            }
        case .uploading:
            self.frameCount = 105
            self.loopDuration = 1.75
            let track = roundedRect(uploadingActivityTrack)
            let container = SimpleLayer()
            container.frame = self.bounds
            let mask = SimpleLayer()
            mask.frame = self.bounds
            for opacity in [Float(1.0), 0.3] {
                let fill = shapeLayer(fill: .black, stroke: nil)
                fill.frame = self.bounds
                fill.path = track
                fill.opacity = opacity
                mask.addSublayer(fill)
            }
            container.mask = mask
            let base = SimpleLayer()
            base.frame = self.bounds
            base.backgroundColor = NSColor(rgb: theme.backgroundColor.rgb).cgColor
            let overlay = SimpleLayer()
            overlay.frame = self.bounds
            overlay.backgroundColor = NSColor(rgb: color.rgb, alpha: 0.3).cgColor
            let bar = shapeLayer(fill: NSColor(rgb: color.rgb), stroke: nil)
            container.addSublayer(base)
            container.addSublayer(overlay)
            container.addSublayer(bar)
            self.addSublayer(container)
            self.shapes.append(Shape(layer: bar, path: { [unowned self] value in
                return self.roundedRect(uploadingBarFrame(value))
            }, opacity: nil))
        case .choosingSticker:
            self.frameCount = 120
            self.loopDuration = 2.0
            let parts: [(ChoosingStickerFrame) -> CGRect] = [{ $0.leftEye }, { $0.leftPupil }, { $0.rightEye }, { $0.rightPupil }]
            for (index, part) in parts.enumerated() {
                let isEye = index % 2 == 0
                let layer = shapeLayer(fill: isEye ? nil : color, stroke: isEye ? color : nil)
                self.shapes.append(Shape(layer: layer, path: { [unowned self] value in
                    return self.ellipse(part(choosingStickerFrame(value)))
                }, opacity: nil))
            }
        default:
            self.frameCount = 42
            self.loopDuration = 0.7
            for index in 0 ..< 3 {
                let layer = shapeLayer(fill: NSColor(rgb: color.rgb), stroke: nil)
                self.shapes.append(Shape(layer: layer, path: { [unowned self] value in
                    return self.ellipse(typingDotsFrame(value)[index].rect)
                }, opacity: { value in
                    return typingDotsFrame(value)[index].alpha
                }))
            }
        }
        for shape in self.shapes where shape.layer.superlayer == nil {
            self.addSublayer(shape.layer)
        }
        self.show(sample: 0)
    }
    
    func show(sample index: Int) {
        let value = CGFloat(index) / CGFloat(self.frameCount)
        for shape in self.shapes {
            shape.layer.frame = self.bounds
            shape.layer.path = shape.path(value)
            if let opacity = shape.opacity {
                shape.layer.opacity = Float(opacity(value))
            }
        }
    }
    
    func startAnimating() {
        let values = (0 ..< self.frameCount).map { CGFloat($0) / CGFloat(self.frameCount) }
        func add(_ layer: CALayer, keyPath: String, _ frameValues: [Any]) {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = frameValues
            animation.duration = self.loopDuration
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: keyPath)
        }
        for shape in self.shapes {
            add(shape.layer, keyPath: "path", values.map { shape.path($0) })
            if let opacity = shape.opacity {
                add(shape.layer, keyPath: "opacity", values.map { NSNumber(value: Float(opacity($0))) })
            }
        }
    }
}

public class ChatActivitiesView : View {
    
    
    private let textView:TextView = TextView()
    private let animationView:NSView = NSView(frame: NSMakeRect(0,-4,30,20))
    let indicatorLayer = ChatActivityIndicatorLayer()
    private var isAnimating:Bool = false
    private var playbackObserver: AnimatableContentObserver?
    
    private var type:ChatActivityAnimation?
    private var theme:ActivitiesTheme?
    
    public override init() {
        super.init()
        animationView.wantsLayer = true
        animationView.layer?.addSublayer(indicatorLayer)
        addSubview(textView)
        addSubview(animationView)
        layer?.disableActions()
        postsFrameChangedNotifications = true
        postsBoundsChangedNotifications = true
        updatePlayback()
    }
    
    public override func layout() {
        super.layout()
        updatePlayback()
    }
    
    public func updateBackground(_ background:NSColor) {
        self.backgroundColor = background
        self.textView.backgroundColor = background
        needsDisplay = true
    }
    
    public func layout(with params:(ChatActivityAnimation, TextViewLayout?), width:CGFloat, theme:ActivitiesTheme) -> Void {
        
        textView.userInteractionEnabled = false
        if params.0 == .none {
            stopAnimation()
        } else {
            startAnimation(params.0, theme:theme)
        }
        if let layout = params.1 {
            setFrameSize(layout.layoutSize.width + animationView.frame.width, layout.layoutSize.height)
        }
        textView.update(params.1, origin:NSMakePoint(animationView.frame.width , 0))
        
        if let type = type {
            switch type {
            case .choosingSticker:
                animationView.setFrameOrigin(NSMakePoint(0, -1))
            default:
                animationView.setFrameOrigin(NSMakePoint(0, -4))
            }
        }
        updatePlayback()
    }
    
    public func startAnimation(_ type:ChatActivityAnimation, theme:ActivitiesTheme) {
        guard type != .none else {
            stopAnimation()
            return
        }
        if self.type != type || theme != self.theme {
            self.type = type
            self.theme = theme
            animationView.setFrameSize(ChatActivityIndicatorLayer.size(for: type))
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            indicatorLayer.frame = animationView.bounds
            indicatorLayer.configure(type, theme: theme)
            indicatorLayer.startAnimating()
            CATransaction.commit()
        }
        isAnimating = true
        updatePlaybackObserver()
        updatePlayback()
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updatePlaybackObserver()
        updatePlayback()
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updatePlaybackObserver()
        updatePlayback()
    }

    public override func viewDidHide() {
        super.viewDidHide()
        updatePlayback()
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        updatePlayback()
    }
    
    var isIndicatorPlaying: Bool {
        return !indicatorLayer.isTimelineFrozen
    }
    
    private func updatePlaybackObserver() {
        guard isAnimating, window != nil else {
            playbackObserver = nil
            return
        }
        if playbackObserver == nil {
            playbackObserver = AnimatableContentObserver()
        }
        playbackObserver?.update(for: self, target: self, selector: #selector(updatePlayback), options: [.contentBounds, .documentFrame, .ownFrame, .ownBounds])
    }

    @objc private func updatePlayback() {
        let playing = isAnimating && WindowKeyObserver.isKey(window) && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty
        indicatorLayer.setTimelineFrozen(!playing)
    }
    
    public func stopAnimation(_ realyStop:Bool = true) {
        if realyStop {
            isAnimating = false
        }
        updatePlaybackObserver()
        updatePlayback()
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}




public class ChatActivitiesModel: Node {

    public private(set) var isActive:Bool = false
    private let activityView:ChatActivitiesView
    private let disposable:MetaDisposable = MetaDisposable()
    public private(set) var theme: ActivitiesTheme?
    private var cachedTextLayout: TextViewLayout?
    private var cachedTextScale: CGFloat = 0
    private var cachedTextColor: CGColor?
    private var cachedSelectionColor: CGColor?
    public func update(with activities:(PeerId, [(Peer, PeerInputActivity)]), for width:CGFloat, theme:ActivitiesTheme, layout:@escaping(Bool)->Void) {
        isActive = !activities.1.isEmpty
        self.theme = theme
        activityView.updateBackground(.clear)
        disposable.set(renderedActivities(activities, for: width, theme:theme).start(next: { [weak self] data in
            self?.activityView.layout(with: data, width: width, theme: theme)
            layout(data.1 != nil)
        }))
    }
    
    private func renderedActivities(_ activities:(PeerId, [(Peer, PeerInputActivity)]), for width:CGFloat, theme: ActivitiesTheme) -> Signal <(ChatActivityAnimation, TextViewLayout?), NoError> {
        return Signal { [weak self] subscriber in
            guard let self else {
                subscriber.putCompletion()
                return EmptyDisposable
            }
            

            if !activities.1.isEmpty {
                let layout:TextViewLayout
                var animation:ChatActivityAnimation = .text
                let text = NSMutableAttributedString()
                var sameActivity:Bool = true
                let isFew:Bool = activities.1.count > 1
                for (_, activity) in activities.1 {
                    if activity != activities.1[0].1 {
                        sameActivity = false
                        break
                    }
                    if case .typingText = activity {
                        sameActivity = false
                        break
                    }
                }
                
                if isFew {
                    let firstTitle: String = activities.1[0].0.displayTitle
                    if sameActivity {
                        let activity = activities.1[0].1
                        switch activity {
                            case .recordingVoice:
                                animation = .recording
                            _ = text.append(string:
                                                strings().peerActivityChatMultiRecordingAudio1(firstTitle, activities.1.count - 1), color: theme.textColor, font: .normal(.text))
                        case .uploadingFile:
                             animation = .uploading
                            _ = text.append(string: strings().peerActivityChatMultiSendingFile1(firstTitle, activities.1.count - 1), color: theme.textColor, font: .normal(.text))
                        case .uploadingPhoto:
                            animation = .uploading
                            _ = text.append(string: strings().peerActivityChatMultiSendingPhoto1(firstTitle, activities.1.count - 1), color: theme.textColor, font: .normal(.text))
                        case .uploadingVideo:
                            animation = .uploading
                            _ = text.append(string: strings().peerActivityChatMultiSendingVideo1(firstTitle, activities.1.count - 1), color: theme.textColor, font: .normal(.text))
                        case .recordingInstantVideo:
                            animation = .recording
                            _ = text.append(string: strings().peerActivityChatMultiRecordingVideo1(firstTitle, activities.1.count - 1), color: theme.textColor, font: .normal(.text))
                        case .choosingSticker:
                            animation = .choosingSticker
                            _ = text.append(string: strings().peerActivityChatMultiChoosingSticker1(firstTitle, activities.1.count - 1), color: theme.textColor, font: .normal(.text))
                        case .playingGame:
                            animation = .text
                            _ = text.append(string: strings().peerActivityChatMultiPlayingGame1(firstTitle, activities.1.count - 1), color: theme.textColor, font: .normal(.text))
                        default:
                            animation = .text
                            _ = text.append(string: strings().peerActivityChatMultiTypingText1(firstTitle, activities.1.count - 1), color: theme.textColor, font: .normal(.text))
                        }
                    } else {
                        animation = .text
                        if activities.1.count > 2 {
                            _ = text.append(string: strings().peerActivityChatMultiTypingText1(firstTitle, activities.1.count - 1), color: theme.textColor, font: .normal(.text))
                        } else {
                            let names = activities.1.map({$0.0.compactDisplayTitle}).joined(separator: ", ")
                            _ = text.append(string: names, color: theme.textColor, font: .normal(.text))
                        }
                    }
                } else {
                    let activity = activities.1[0].1
                    let peer = activities.1[0].0
                    switch activity {
                    case .recordingVoice:
                        animation = .recording
                        if activities.0.namespace == Namespaces.Peer.CloudUser || activities.0.namespace == Namespaces.Peer.SecretChat {
                            _ = text.append(string: strings().peerActivityUserRecordingAudio, color: theme.textColor, font: .normal(.text))
                        } else {
                            _ = text.append(string: strings().peerActivityChatRecordingAudio(peer.compactDisplayTitle), color: theme.textColor, font: .normal(.text))
                        }
                    case .uploadingFile:
                        animation = .uploading
                        if activities.0.namespace == Namespaces.Peer.CloudUser || activities.0.namespace == Namespaces.Peer.SecretChat {
                            
                            _ = text.append(string: strings().peerActivityUserSendingFile, color: theme.textColor, font: .normal(.text))
                        } else {
                            _ = text.append(string: strings().peerActivityChatSendingFile(peer.compactDisplayTitle), color: theme.textColor, font: .normal(.text))
                        }
                    case .uploadingVideo:
                        animation = .uploading
                        if activities.0.namespace == Namespaces.Peer.CloudUser || activities.0.namespace == Namespaces.Peer.SecretChat {
                            
                            _ = text.append(string: strings().peerActivityUserSendingVideo, color: theme.textColor, font: .normal(.text))
                        } else {
                            _ = text.append(string: strings().peerActivityChatSendingVideo(peer.compactDisplayTitle), color: theme.textColor, font: .normal(.text))
                        }
                    case .uploadingPhoto:
                        animation = .uploading
                        if activities.0.namespace == Namespaces.Peer.CloudUser || activities.0.namespace == Namespaces.Peer.SecretChat {
                            
                            _ = text.append(string: strings().peerActivityUserSendingPhoto, color: theme.textColor, font: .normal(.text))
                        } else {
                            _ = text.append(string: strings().peerActivityChatSendingPhoto(peer.compactDisplayTitle), color: theme.textColor, font: .normal(.text))
                        }
                    case .choosingSticker:
                        animation = .choosingSticker
                        if activities.0.namespace == Namespaces.Peer.CloudUser || activities.0.namespace == Namespaces.Peer.SecretChat {
                            
                            _ = text.append(string: strings().peerActivityUserChoosingSticker, color: theme.textColor, font: .normal(.text))
                        } else {
                            _ = text.append(string: strings().peerActivityChatChoosingSticker(peer.compactDisplayTitle), color: theme.textColor, font: .normal(.text))
                        }
                    case let .seeingEmojiInteraction(emoticon):
                        animation = .choosingSticker
                        if activities.0.namespace == Namespaces.Peer.CloudUser || activities.0.namespace == Namespaces.Peer.SecretChat {
                            
                            _ = text.append(string: strings().peerActivityUserEnjoyingAnimations(emoticon), color: theme.textColor, font: .normal(.text))
                        } else {
                            _ = text.append(string: strings().peerActivityChatEnjoyingAnimations(peer.compactDisplayTitle, emoticon), color: theme.textColor, font: .normal(.text))
                        }
                    case .recordingInstantVideo:
                        animation = .recording
                        if activities.0.namespace == Namespaces.Peer.CloudUser || activities.0.namespace == Namespaces.Peer.SecretChat {
                            _ = text.append(string: strings().peerActivityUserRecordingVideo, color: theme.textColor, font: .normal(.text))
                        } else {
                            _ = text.append(string: strings().peerActivityChatRecordingVideo(peer.compactDisplayTitle), color: theme.textColor, font: .normal(.text))
                        }
                    case .playingGame:
                        animation = .text
                        if activities.0.namespace == Namespaces.Peer.CloudUser || activities.0.namespace == Namespaces.Peer.SecretChat {
                            _ = text.append(string: strings().peerActivityUserPlayingGame, color: theme.textColor, font: .normal(.text))
                        } else {
                            _ = text.append(string: strings().peerActivityChatPlayingGame(peer.compactDisplayTitle), color: theme.textColor, font: .normal(.text))
                        }
                    default:
                        animation = .text
                        if activities.0.namespace == Namespaces.Peer.CloudUser || activities.0.namespace == Namespaces.Peer.SecretChat {
                            _ = text.append(string: strings().peerActivityUserTypingText, color: theme.textColor, font: .normal(.text))
                        } else {
                            _ = text.append(string: strings().peerActivityChatTypingText(peer.compactDisplayTitle), color: theme.textColor, font: .normal(.text))
                        }
                    }
                }
                
                layout = self.activityTextLayout(text, width: width - 30, color: theme.textColor)
                subscriber.putNext((animation, layout))
                subscriber.putCompletion()
            } else {
                self.cachedTextLayout = nil
                self.cachedTextColor = nil
                self.cachedSelectionColor = nil
                subscriber.putNext((.none, nil))
                subscriber.putCompletion()
            }
            
            return EmptyDisposable
        } |> deliverOnMainQueue
    }

    private func activityTextLayout(_ text: NSAttributedString, width: CGFloat, color: NSColor) -> TextViewLayout {
        let scale = System.backingScale
        let resolvedColor = color.cgColor
        let selectionColor = presentation.colors.selectText.cgColor
        if let layout = cachedTextLayout,
           layout.constrainedWidth == width,
           cachedTextScale == scale,
           cachedTextColor == resolvedColor,
           cachedSelectionColor == selectionColor,
           layout.attributedString.isEqual(to: text) {
            return layout
        }
        let layout = TextViewLayout(text, maximumNumberOfLines: 1)
        layout.measure(width: width)
        cachedTextLayout = layout
        cachedTextScale = scale
        cachedTextColor = resolvedColor
        cachedSelectionColor = selectionColor
        return layout
    }
    
    deinit {
        disposable.dispose()
    }
    
    public func clean() {
        disposable.set(nil)
        cachedTextLayout = nil
        cachedTextColor = nil
        cachedSelectionColor = nil
        activityView.stopAnimation()
    }
    
    public init() {
        self.activityView = ChatActivitiesView()
        super.init(activityView)
    }
    
}
