import Cocoa
import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import ColorPalette
import TgVoipWebrtc
import CallsUI
import Localization
import TelegramCallsCore
import TelegramTheme
import TelegramUtils

private final class SelfPresentationPlaceholder : View {
    private let textView = TextView()
    private let button = TextButton()
    private let visualEffect = NSVisualEffectView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(visualEffect)
        addSubview(textView)
        addSubview(button)
        
        button.autohighlight = false
        button.scaleOnClick = true
        
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        
        visualEffect.wantsLayer = true
        visualEffect.material = .ultraDark
        visualEffect.blendingMode = .withinWindow
        visualEffect.state = .active
    }
        
    func update(stop: @escaping()->Void) {
        
        let textLayout = TextViewLayout(.initialize(string: strings().voiceChatSharingPlaceholder, color: GroupCallTheme.customTheme.textColor, font: .medium(.text)), alignment: .center)
        textLayout.measure(width: frame.width - 40)
        textView.update(textLayout)
        
        button.set(text: strings().voiceChatSharingStop, for: .Normal)
        button.set(font: .medium(.text), for: .Normal)
        button.set(color: GroupCallTheme.customTheme.textColor, for: .Normal)
        button.sizeToFit(NSMakeSize(50, 10), .zero, thatFit: false)
        button.set(background: .clear, for: .Normal)
        button.set(background: .clear, for: .Highlight)
        button.setGlassEffect(forceAppearance: .forceDark)
        
        button.removeAllHandlers()
        button.set(handler: { _ in
            stop()
        }, for: .SingleClick)
    }
    
    override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }
    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        textView.resize(frame.width - 40)
        var textRect = size.bounds.focus(textView.frame.size)
        textRect.origin.y = frame.midY - textView.frame.height - 5
        transition.updateFrame(view: textView, frame: textRect)
        
        var buttonRect = size.bounds.focus(button.frame.size)
        buttonRect.origin.y = frame.midY + 5
        transition.updateFrame(view: button, frame: buttonRect)
        
        if let window = window {
            visualEffect.frame = window.bounds
        }
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


public final class GroupCallMainVideoContainerView: Control {
    private let call: PresentationGroupCall
    
    private class V : NSVisualEffectView {
        override var mouseDownCanMoveWindow: Bool {
            return true
        }
    }
    
    public private(set) var currentVideoView: GroupVideoView?
    public private(set) var currentPeer: DominantVideo?
    
    public let shadowView: ShadowView = ShadowView()
    
    private var validLayout: CGSize?
    
    private let nameView: TextView = TextView()
    private let statusView = ImageView()
    
    private let speakingView: View = View()
    private let audioLevelDisposable = MetaDisposable()
    
    private var arguments: GroupCallUIArguments?
    
    private var backView: ImageButton?
    private var pinView: ImageButton?

    
    private var pausedTextView: TextView?
    private var pausedImageView: ImageView?
    
    
    private var selfPresentationPlaceholder: SelfPresentationPlaceholder?
    
    public init(call: PresentationGroupCall) {
        self.call = call
        super.init()
        
        
        speakingView.layer?.cornerRadius = 20
        speakingView.layer?.borderWidth = 2
        speakingView.layer?.borderColor = GroupCallTheme.speakActiveColor.cgColor
        
        self.backgroundColor =  GroupCallTheme.membersColor
        addSubview(shadowView)
        
        shadowView.shadowBackground = NSColor.black.withAlphaComponent(0.3)
        shadowView.direction = .vertical(true)
        
        self.layer?.cornerRadius = 20
        
        addSubview(nameView)
        addSubview(statusView)
        
        self.forceMouseDownCanMoveWindow = true
        

        nameView.userInteractionEnabled = false
        nameView.isSelectable = false
        
        statusView.isEventLess = true
                
        addSubview(speakingView)
        
        self.set(handler: { [weak self] _ in
            if let dominant = self?.currentPeer, self?.isPinned == false {
                self?.arguments?.focusVideo(dominant.endpointId)
            }
        }, for: .SingleClick)
        
        self.set(handler: { [weak self] control in
            if let data = self?.participant {
                if let menuItems = self?.arguments?.contextMenuItems(data), let event = NSApp.currentEvent {
                    ContextMenu.show(items: menuItems, view: control, event: event, presentation: .current(TelegramThemeHooks.shared.darkAppearance().colors), isLegacy: false)
                }
            }
        }, for: .RightDown)
                
        self.set(handler: { [weak self] control in
            self?.pinView?.change(opacity: self?.pinIsVisible == true ? 1 : 0, animated: true)
            self?.backView?.change(opacity: self?.pinIsVisible == true ? 1 : 0, animated: true)
        }, for: .Hover)
        
        self.set(handler: { [weak self] control in
            self?.pinView?.change(opacity: self?.pinIsVisible == true ? 1 : 0, animated: true)
            self?.backView?.change(opacity: self?.pinIsVisible == true ? 1 : 0, animated: true)
        }, for: .Highlight)
        
        self.set(handler: { [weak self] control in
            self?.pinView?.change(opacity: 0, animated: true)
            self?.backView?.change(opacity: 0, animated: true)
        }, for: .Normal)
        
    }
    
    private var pinIsVisible: Bool {
        return ((self.isFocused && !isAlone) || self.isPinned)
    }
    
    public override var mouseDownCanMoveWindow: Bool {
        return true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public func updateMode(controlsMode: GroupCallView.ControlsMode, controlsState: GroupCallControlsView.Mode, animated: Bool) {
        shadowView.change(opacity: controlsMode == .normal ? 1 : 0, animated: animated)
        
        nameView.change(opacity: controlsMode == .normal ? 1 : 0, animated: animated)
        statusView.change(opacity: controlsMode == .normal ? 1 : 0, animated: animated)
        self.pinView?.change(opacity: self.mouseInside() && self.pinIsVisible ? 1 : 0, animated: animated)
        self.backView?.change(opacity: self.mouseInside() && self.pinIsVisible ? 1 : 0, animated: animated)
    }
    
    private var participant: PeerGroupCallData?
    
    private var isPinned: Bool = false
    private var isFocused: Bool = false
    private var isAlone: Bool = false
    public func updatePeer(peer: DominantVideo?, participant: PeerGroupCallData?, resizeMode: CALayerContentsGravity, transition: ContainedViewLayoutTransition, animated: Bool, controlsMode: GroupCallView.ControlsMode, isPinned: Bool, isFocused: Bool, isAlone: Bool, arguments: GroupCallUIArguments?) {
        
       
        self.isFocused = isFocused
        self.isPinned = isPinned
        self.isAlone = isAlone
        self.arguments = arguments
        
        
        self.nameView.isHidden = peer?.endpointId == DominantVideo.streamEndpoint
        self.statusView.isHidden = peer?.endpointId == DominantVideo.streamEndpoint

        if self.pinIsVisible {
            let currentPinView: ImageButton
            if let current = self.pinView {
                currentPinView = current
            } else {
                currentPinView = ImageButton()
                currentPinView.autohighlight = false
                currentPinView.scaleOnClick = true
                currentPinView.setGlassEffect(forceAppearance: .forceDark)
                currentPinView.frame = NSMakeRect(frame.width - 36 - 10, 10, 36, 36)
                currentPinView.layer?.opacity = self.mouseInside() && pinIsVisible ? 1 : 0
                self.pinView = currentPinView
                addSubview(currentPinView)
                currentPinView.set(handler: { [weak self] _ in
                    if let strongSelf = self, let dominant = strongSelf.currentPeer {
                        if !strongSelf.isPinned {
                            self?.arguments?.pinVideo(dominant)
                        } else {
                            self?.arguments?.unpinVideo()
                        }
                    }
                }, for: .SingleClick)

                if currentPinView.layer?.opacity != 0, animated {
                    currentPinView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            currentPinView.set(image: !self.isPinned ? GroupCallTheme.pin_video : GroupCallTheme.unpin_video, for: .Normal)
            currentPinView.setAccessibilityLabel(!self.isPinned ? strings().voiceOverCommonPin : strings().voiceOverCommonUnpin)
            currentPinView.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)


        } else {
            if let view = pinView {
                self.pinView = nil
                if animated {
                    if view.layer?.opacity != 0 {
                        view.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak view] _ in
                            view?.removeFromSuperview()
                        })
                    } else {
                        view.removeFromSuperview()
                    }
                } else {
                    view.removeFromSuperview()
                }
            }
        }
        
        if pinIsVisible {
            let currentBackView: ImageButton
            if let current = self.backView {
                currentBackView = current
            } else {
                currentBackView = ImageButton()
                currentBackView.autohighlight = false
                currentBackView.scaleOnClick = true
                currentBackView.setGlassEffect(forceAppearance: .forceDark)
                currentBackView.set(image: GroupCallTheme.video_back, for: .Normal)
                currentBackView.setAccessibilityLabel(strings().voiceOverCommonBack)
                currentBackView.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
                currentBackView.frame = NSMakeRect(10, 10, 36, 36)
                currentBackView.layer?.opacity = self.mouseInside() && pinIsVisible ? 1 : 0
                self.backView = currentBackView
                addSubview(currentBackView)
                currentBackView.set(handler: { [weak self] _ in
                    self?.arguments?.focusVideo(nil)
                }, for: .SingleClick)

                if currentBackView.layer?.opacity != 0, animated {
                    currentBackView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
        } else {
            if let view = backView {
                self.backView = nil
                if animated {
                    if view.layer?.opacity != 0 {
                        view.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak view] _ in
                            view?.removeFromSuperview()
                        })
                    } else {
                        view.removeFromSuperview()
                    }
                } else {
                    view.removeFromSuperview()
                }
            }
        }

        self.pinView?.change(opacity: self.mouseInside() && pinIsVisible ? 1 : 0, animated: animated)
        self.backView?.change(opacity: self.mouseInside() && pinIsVisible ? 1 : 0, animated: animated)

        
        
        let showSpeakingView = participant?.isSpeaking == true && (participant?.state?.muteState?.mutedByYou == nil || participant?.state?.muteState?.mutedByYou == false)
        
        transition.updateAlpha(view: speakingView, alpha: showSpeakingView ? 1 : 0)
        
        speakingView.layer?.borderColor = participant?.state?.muteState?.mutedByYou == true ? GroupCallTheme.customTheme.redColor.cgColor : GroupCallTheme.speakActiveColor.cgColor
                
        transition.updateAlpha(view: shadowView, alpha: controlsMode == .normal ? 1 : 0)
        transition.updateAlpha(view: nameView, alpha: controlsMode == .normal ? 1 : 0)
        transition.updateAlpha(view: statusView, alpha: controlsMode == .normal ? 1 : 0)
        
        
        if participant != self.participant, let participant = participant {
            let text: String
            if participant.peer.id == participant.accountPeerId {
                text = strings().voiceChatStatusYou
            } else {
                text = participant.peer.displayTitle
            }
            let nameLayout = TextViewLayout(.initialize(string: text, color: NSColor.white.withAlphaComponent(1), font: .medium(.short)), maximumNumberOfLines: 1)
            nameLayout.measure(width: frame.width - 20)
            self.nameView.update(nameLayout)
            
            self.statusView.image = participant.state?.muteState == nil ? GroupCallTheme.videoBox_unmuted : GroupCallTheme.videoBox_muted
            self.statusView.setAccessibilityLabel(participant.state?.muteState != nil ? strings().voiceOverCommonMuted : participant.isSpeaking ? strings().voiceChatStatusSpeaking : nil)
            self.statusView.sizeToFit()
        }
        self.currentPeer = peer
        if let peer = peer {
            
            var selfPresentation = peer.peerId == arguments?.getAccountPeerId() && peer.mode == .screencast
            
            if let source = arguments?.getSource(.screencast) {
                if source.deviceIdKey().hasPrefix("desktop_capturer_window") {
                    selfPresentation = false
                }
            }
            
            if selfPresentation {
                
                let current: SelfPresentationPlaceholder
                if let c = self.selfPresentationPlaceholder {
                    current = c
                } else {
                    current = SelfPresentationPlaceholder(frame: self.bounds)
                    self.selfPresentationPlaceholder = current
                    addSubview(current)
                    
                    if animated {
                        current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    }
                }
            
                
                current.update(stop: { [weak arguments] in
                    arguments?.cancelShareScreencast()
                })
            } else {
                if let view = self.selfPresentationPlaceholder {
                    self.selfPresentationPlaceholder = nil
                    if animated {
                        view.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak view] _ in
                            view?.removeFromSuperview()
                        })
                    } else {
                        view.removeFromSuperview()
                    }
                }
            }

            
            let videoView = arguments?.takeVideo(peer.peerId, peer.mode, .main) as? GroupVideoView
            let isPaused = participant?.isVideoPaused(peer.endpointId) == true && !selfPresentation

            if let videoView = videoView, self.currentVideoView != videoView || videoView.superview != self {
                if let currentVideoView = self.currentVideoView {
                    currentVideoView.removeFromSuperview()
                }
                self.currentVideoView = videoView
                self.addSubview(videoView, positioned: .below, relativeTo: self.shadowView)
            }
            
            if let videoView = videoView {
                
                videoView._change(opacity: isPaused ? 0 : 1, animated: animated)
                
                let prevIsPaused = self.participant?.isVideoPaused(peer.endpointId) == true
                if prevIsPaused != isPaused {
                    if isPaused {
                        self.pausedTextView?.removeFromSuperview()
                        self.pausedImageView?.removeFromSuperview()
                        self.pausedTextView = TextView()
                        self.pausedImageView = ImageView()
                        self.pausedImageView?.isAccessibilityDecorative = true
                        self.pausedImageView?.image = GroupCallTheme.video_paused
                        self.pausedImageView?.sizeToFit()
                        let layout = TextViewLayout(.initialize(string: peer.mode == .video ? strings().voiceChatVideoPaused : strings().voiceChatScreencastPaused, color: GroupCallTheme.customTheme.textColor, font: .medium(.text)))
                        layout.measure(width: .greatestFiniteMagnitude)
                        self.pausedTextView?.update(layout)
                        addSubview(self.pausedTextView!)
                        addSubview(self.pausedImageView!)
                        
                        
                        self.pausedImageView!.frame = focus(pausedImageView!.frame.size).offsetBy(dx: 0, dy: -5)
                        self.pausedTextView!.frame = self.pausedTextView!.centerFrameX(y: self.pausedImageView!.frame.maxY + 5)
                        if animated {
                            pausedTextView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                            pausedImageView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                        }
                    } else {
                        if let pausedTextView = pausedTextView {
                            self.pausedTextView = nil
                            if animated {
                                pausedTextView.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak pausedTextView] _ in
                                    pausedTextView?.removeFromSuperview()
                                })
                            } else {
                                pausedTextView.removeFromSuperview()
                            }
                        }
                        if let pausedImageView = pausedImageView {
                            self.pausedImageView = nil
                            if animated {
                                pausedImageView.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak pausedImageView] _ in
                                    pausedImageView?.removeFromSuperview()
                                })
                            } else {
                                pausedImageView.removeFromSuperview()
                            }
                        }
                    }
                }
            }
            
            
            self.currentVideoView?.gravity = resizeMode
            
        } else {
            if let view = self.selfPresentationPlaceholder {
                view.removeFromSuperview()
                self.selfPresentationPlaceholder = nil
            }
            
            if let currentVideoView = self.currentVideoView {
                currentVideoView.removeFromSuperview()
                self.currentVideoView = nil
            }
        }
        self.participant = participant

        self.updateLayout(size: self.frame.size, transition: transition)
    }
    
    public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        
        
        self.validLayout = size
        if let currentVideoView = self.currentVideoView {
            transition.updateFrame(view: currentVideoView, frame: size.bounds)
            currentVideoView.updateLayout(size: size, transition: transition)
        }
        
        
        transition.updateFrame(view: shadowView, frame: CGRect(origin: NSMakePoint(0, size.height - 50), size: NSMakeSize(size.width, 50)))
        
        
        self.nameView.resize(size.width - 40)

        
        transition.updateFrame(view: statusView, frame: CGRect(origin: NSMakePoint(5, size.height - 5 - self.statusView.frame.height), size: self.statusView.frame.size))
        transition.updateFrame(view: self.nameView, frame: CGRect(origin: NSMakePoint(statusView.frame.maxX + 5, size.height - 5 - self.nameView.frame.height), size: self.nameView.frame.size))
        
        transition.updateFrame(view: speakingView, frame: bounds)
        
        if let pausedImageView = pausedImageView {
            transition.updateFrame(view: pausedImageView, frame: focus(pausedImageView.frame.size).offsetBy(dx: 0, dy: -10))
            if let pausedTextView = pausedTextView {
                transition.updateFrame(view: pausedTextView, frame: pausedTextView.centerFrameX(y: pausedImageView.frame.maxY + 5))
            }
        }
        
        
        if let pinView = pinView {
            let pinRect = NSMakeRect(frame.width - 36 - 10, 10, 36, 36)
            transition.updateFrame(view: pinView, frame: pinRect)
            pinView.updateLayout(size: pinRect.size, transition: transition)
        }
        if let backView = self.backView {
            let backRect = NSMakeRect(10, 10, 36, 36)
            transition.updateFrame(view: backView, frame: backRect)
            backView.updateLayout(size: backRect.size, transition: transition)
        }
        
        if let view = self.selfPresentationPlaceholder {
            transition.updateFrame(view: view, frame: size.bounds)
            view.updateLayout(size: size, transition: transition)
        }
    }
    
    deinit {
        audioLevelDisposable.dispose()
    }
    
    
    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }
}
