import Cocoa
import SceneEffects
import Postbox
import TelegramCore
import InAppSettings
import TGUIKit
import SwiftSignalKit
import TelegramMedia
import FoundationUtils
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import TelegramMediaResources
import Localization
import ColorPalette
import MessageUtils
import ChatModeTypes


public class SlotsMediaContentView: ChatMediaContentView {
    private let idlePlayer: LottiePlayerView = LottiePlayerView(frame: NSMakeRect(0, 0, 240, 240))
    private let pullPlayer: LottiePlayerView = LottiePlayerView(frame: NSMakeRect(0, 0, 240, 240))

    private let spin1Player: LottiePlayerView = LottiePlayerView(frame: NSMakeRect(0, 0, 240, 240))
    private let spin2Player: LottiePlayerView = LottiePlayerView(frame: NSMakeRect(0, 0, 240, 240))
    private let spin3Player: LottiePlayerView = LottiePlayerView(frame: NSMakeRect(0, 0, 240, 240))

    
    private var value: SlotMachineValue = SlotMachineValue(rawValue: nil)
    
    private let thumbView = TransformImageView()
    private let loadResourceDisposable = MetaDisposable()
    private let stateDisposable = MetaDisposable()
    private let view = NSView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        view.addSubview(self.idlePlayer)
        view.addSubview(self.spin1Player)
        view.addSubview(self.spin2Player)
        view.addSubview(self.spin3Player)
        view.addSubview(self.pullPlayer)
        view.addSubview(self.thumbView)
        
        addSubview(view)
        view.frame = bounds
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func clean() {
        loadResourceDisposable.dispose()
    }
    
    deinit {
        clean()
    }
    
    public func removeNotificationListeners() {
        NotificationCenter.default.removeObserver(self)
    }
    
    public override func viewDidUpdatedDynamicContent() {
        super.viewDidUpdatedDynamicContent()
        updatePlayerIfNeeded()
    }
    
    
    
    
    @objc public func updatePlayerIfNeeded() {
        
    }
    
    
    public override func executeInteraction(_ isControl: Bool) {
        
        let media = self.media as? TelegramMediaDice
        
        if let media = media, let message = self.parent {
            let item = self.table?.item(stableId: ChatHistoryEntryId.message(message))
            
            if let item = item as? ChatMediaParentRowItem, let peer = item.peer, peer.canSendMessage(item.chatInteraction.mode.isThreadMode) {
                let text: String
                
                switch media.emoji {
                case diceSymbol:
                    text = strings().chatEmojiDiceResultNew
                case dartSymbol:
                    text = strings().chatEmojiDartResultNew
                default:
                    text = strings().chatEmojiDefResultNew(media.emoji)
                }
                let view: NSView
                if !thumbView.isHidden {
                    view = thumbView
                } else {
                    view = idlePlayer
                }
                tooltip(for: view, text: text, interactions: LinkHooks.shared.globalLinkExecutor(), button: (strings().chatEmojiSend, { [weak item] in
                    item?.chatInteraction.sendPlainText(media.emoji)
                }), offset: NSMakePoint(0, -30))
            }
        }
    }
    
    public var chatLoopAnimated: Bool {
        if let context = self.context {
            return context.autoplayMedia.loopAnimatedStickers
        }
        return true
    }
    
    private let animatableContentObserver = AnimatableContentObserver()

    public func updateListeners() {
        animatableContentObserver.update(for: self, target: self, selector: #selector(updatePlayerIfNeeded), options: [.contentBounds, .documentFrame])
    }
    
    public override func viewWillDraw() {
        super.viewWillDraw()
        updatePlayerIfNeeded()
    }
    
    public override func willRemove() {
        super.willRemove()
        updateListeners()
        updatePlayerIfNeeded()
    }
    
    public override func viewDidMoveToSuperview() {
        updateListeners()
        updatePlayerIfNeeded()
    }
    
    public override func viewDidMoveToWindow() {
        updateListeners()
        updatePlayerIfNeeded()
    }
    
    public var players:[LottiePlayerView] {
        return [idlePlayer, pullPlayer, spin1Player, spin2Player, spin3Player]
    }
    
    public override func update(with media: Media, size: NSSize, context: any AccountContextProtocol, parent: Message?, table: TableView?, parameters: ChatMediaLayoutParameters?, animated: Bool, positionFlags: LayoutPositionFlags?, approximateSynchronousValue: Bool) {
        
        
        
        if parent?.stableId != self.parent?.stableId {
            _ = players.map {
                $0.set(nil)
            }
        }
        
        
        super.update(with: media, size: size, context: context, parent: parent, table: table, parameters: parameters, animated: animated, positionFlags: positionFlags, approximateSynchronousValue: approximateSynchronousValue)
        
        
        guard let media = media as? TelegramMediaDice, let parent = parent else {
            return
        }
        
        let value = SlotMachineValue(rawValue: media.value)
        let previousValue = self.value
        self.value = value
        
        let sent: Bool = media.value != nil
        
        let played: Bool = parameters?.dicePlayed(parent) ?? true
        
        
        
        let data: Signal<[(String, Data?, TelegramMediaFile)], NoError> = context.diceCache.interactiveSymbolData(baseSymbol: media.emoji, synchronous: approximateSynchronousValue)
        
       
        if previousValue != value {
            _ = players.map {
                $0.animation?.triggerOn = nil
                $0.animation?.onFinish = nil
            }
        }
        
        let spinPolicy: LottiePlayPolicy
        if sent {
            if played {
                spinPolicy = .toEnd(from: .max)
            } else {
                spinPolicy = .onceEnd
            }
        } else {
            spinPolicy = .loop
        }
        
        self.loadResourceDisposable.set((data |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let `self` = self else {
                return
            }
            

            
            if data.count < 21 {
                return
            }
            
            let idleData = data[1]
            if let data = idleData.1 {
                let policy: LottiePlayPolicy
                if value.jackpot && !played {
                    policy = .onceEnd
                } else {
                    policy = .onceToFrame(1)
                }
                let animation = LottieAnimation(compressed: data, key: LottieAnimationEntryKey(key: .media(idleData.2.id), size: size), cachePurpose: .temporaryLZ4(.chat), playPolicy: policy, maximumFps: 30)
                self.idlePlayer.set(animation)
            }
            let pullData = data[2]
            if let data = pullData.1 {
                let animation = LottieAnimation(compressed: data, key: LottieAnimationEntryKey(key: .media(pullData.2.id), size: size), cachePurpose: .temporaryLZ4(.chat), playPolicy: played ? .toEnd(from: .max) : .onceEnd, maximumFps: 30)
                self.pullPlayer.set(animation)
            }
            
            let indexes = value.packIndex
            
            
            
            let spinViews:[LottiePlayerView] = [self.spin1Player, self.spin2Player, self.spin3Player]
            
            for (i, index) in indexes.enumerated() {
                let view = spinViews[i]
                let spinData = data[index]
                if let data = spinData.1 {
                    let animation = LottieAnimation(compressed: data, key: LottieAnimationEntryKey(key: .media(spinData.2.id), size: size), cachePurpose: .temporaryLZ4(.chat), playPolicy: spinPolicy, maximumFps: 30)
                    if sent && view.contextAnimation != nil {
                        view.contextAnimation?.triggerOn = (.first, { [weak view] in
                            view?.set(animation)
                        }, {})
                    } else {
                        view.set(animation)
                    }
                    if sent {
                        animation.onFinish = {
                            parameters?.markDiceAsPlayed(parent)
                            if !played, value.is777, !parent.isIncoming(context.account, theme.bubbled) {
                                PlayConfetti(for: context.window)
                            }
                        }
                    }
                }
            }
            
        }))
        
        let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: size, boundingSize: size, intrinsicInsets: NSEdgeInsets())
        
        self.thumbView.setSignal(signal: cachedSlot(value: value, arguments: arguments, scale: self.backingScaleFactor), clearInstantly: true)
        //if !self.thumbView.isFullyLoaded {
        self.thumbView.setSignal(chatMessageSlotSticker(postbox: context.account.postbox, value: value, scale: self.backingScaleFactor, size: size), cacheImage: { result in
            cacheSlot(result, value: value, arguments: arguments, scale: System.backingScale)
        })
        self.thumbView.set(arguments: arguments)
        
        
        self.stateDisposable.set((self.spin1Player.state |> deliverOnMainQueue).start(next: { [weak self] state in
            guard let `self` = self else { return }
            switch state {
            case .playing:
                self.thumbView.isHidden = true
            case .stoped:
                switch spinPolicy {
                case .onceEnd:
                    self.thumbView.isHidden = true
                default:
                    self.thumbView.isHidden = false
                }
            default:
                break
            }
        }))

    }
    
    public override func layout() {
        super.layout()
        view.frame = bounds
        _ = players.map {
            $0.frame = bounds
        }
        self.thumbView.frame = bounds
    }
    
}

