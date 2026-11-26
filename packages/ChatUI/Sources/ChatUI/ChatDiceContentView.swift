import Cocoa
import SceneEffects
import Postbox
import TelegramCore
import InAppSettings
import TGUIKit
import SwiftSignalKit
import TelegramMedia
import CurrencyFormat
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
import DiceCache

public let diceSide1: String = "1⃣"
public let diceSide2: String = "2⃣"
public let diceSide3: String = "3⃣"
public let diceSide4: String = "4⃣"
public let diceSide5: String = "5⃣"
public let diceSide6: String = "6⃣"
public let diceSide7: String = "7⃣"
public let diceSide8: String = "8⃣"
public let diceSide9: String = "9⃣"


private func getIndex(_ string: String) -> Int {
    switch string {
    case diceSide1:
        return 1
    case diceSide2:
        return 2
    case diceSide3:
        return 3
    case diceSide4:
        return 5
    case diceSide5:
        return 5
    case diceSide6:
        return 6
    default:
        return 0
    }
}



private extension Int32 {
    var diceSide: String {
        switch self {
        case 1:
            return diceSide1
        case 2:
            return diceSide2
        case 3:
            return diceSide3
        case 4:
            return diceSide4
        case 5:
            return diceSide5
        case 6:
            return diceSide6
        case 7:
            return diceSide7
        case 8:
            return diceSide8
        case 9:
            return diceSide9
        default:
            preconditionFailure()
        }
    }
}


private enum DicePlay : Equatable {
    case idle
    case failed
    case end(animated: Bool)
}

private struct DiceState : Equatable {
    let messageId: MessageId
    let message: Message
    let play: DicePlay
    
    static func ==(lhs: DiceState, rhs: DiceState) -> Bool {
        return lhs.play == rhs.play && isEqualMessages(lhs.message, rhs.message)
    }
    
    init(message: Message, played: Bool) {
        self.message = message
        self.messageId = message.id
        if let dice = message.anyMedia as? TelegramMediaDice, dice.value == 0 {
            play = .idle
        } else if message.forwardInfo != nil {
            play = .end(animated: false)
        } else {
            if message.flags.contains(.Failed) {
                self.play = .failed
            } else if message.flags.isSending {
                play = .idle
            } else {
                if !played {
                    play = .end(animated: true)
                } else {
                    play = .end(animated: false)
                }
            }
        }
        
    }
}

public class ChatDiceContentView: ChatMediaContentView {
    private let playerView: LottiePlayerView = LottiePlayerView(frame: NSMakeRect(0, 0, 240, 240))
    private let thumbView = TransformImageView()
    private let loadResourceDisposable = MetaDisposable()
    private let stateDisposable = MetaDisposable()
    private var diceState: DiceState?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(self.playerView)
        addSubview(self.thumbView)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func clean() {
        loadResourceDisposable.dispose()
    }
    
    deinit {
        clean()
        stateDisposable.dispose()
        removeNotificationListeners()
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

        if let media = media, let message = self.parent, let context = self.context {
            let item = self.table?.item(stableId: ChatHistoryEntryId.message(message))

            if let item = item as? ChatMediaParentRowItem, let peer = item.peer, peer.canSendMessage(item.chatInteraction.mode.isThreadMode, media: message.media.first) {

                let view: NSView
                if !thumbView.isHidden {
                    view = thumbView
                } else {
                    view = playerView
                }

                if media.emoji == diceSymbol, case let .available(info) = context.emojiGameInfo {
                    let text = strings().diceRollYourStake(formatCurrencyAmount(info.previousStake, currency: TON).prettyCurrencyNumber)
                    let attr = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(.text), textColor: .white), bold: MarkdownAttributeSet(font: .bold(.text), textColor: .white), link: MarkdownAttributeSet(font: .normal(.text), textColor: .link), linkAttribute: { [weak item] _ in
                        return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink("", { _ in
                            item?.chatInteraction.diceRoll()
                        }))
                    }))

                    tooltip(for: view, text: "", attributedText: attr, interactions: LinkHooks.shared.globalLinkExecutor(), button: (strings().chatEmojiSend, { [weak item] in
                        if info.previousStake > 0 {
                            item?.chatInteraction.sendDiceWithStake(info.previousStake)
                        } else {
                            item?.chatInteraction.sendPlainText(media.emoji)
                        }
                    }), offset: NSMakePoint(0, -30), buttonSpacing: 50)
                } else {
                    let text: String
                    switch media.emoji {
                    case diceSymbol:
                        text = strings().chatEmojiDiceResultNew
                    case dartSymbol:
                        text = strings().chatEmojiDartResultNew
                    default:
                        text = strings().chatEmojiDefResultNew(media.emoji)
                    }
                    tooltip(for: view, text: text, interactions: LinkHooks.shared.globalLinkExecutor(), button: (strings().chatEmojiSend, { [weak item] in
                        item?.chatInteraction.sendPlainText(media.emoji)
                    }), offset: NSMakePoint(0, -30))
                }
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
    
    public override func update(with media: Media, size: NSSize, context: any AccountContextProtocol, parent: Message?, table: TableView?, parameters: ChatMediaLayoutParameters?, animated: Bool, positionFlags: LayoutPositionFlags?, approximateSynchronousValue: Bool) {
        
        
        if parent?.stableId != self.parent?.stableId {
            self.playerView.set(nil)
        }
        
        super.update(with: media, size: size, context: context, parent: parent, table: table, parameters: parameters, animated: animated, positionFlags: positionFlags, approximateSynchronousValue: approximateSynchronousValue)
        
        guard let media = media as? TelegramMediaDice, let parent = parent else {
            return
        }
        
        let baseSymbol: String = media.emoji
        let sideSymbol: String
        
        let currentValue = media.value
        
        if let currentValue = currentValue, currentValue > 0 && currentValue <= 9 {
            sideSymbol = currentValue.diceSide
        } else {
            sideSymbol = diceIdle
        }
    
        let settings = InteractiveEmojiConfiguration.with(appConfiguration: context.appConfiguration)
        
        let diceState = DiceState(message: parent, played: parameters?.dicePlayed(parent) ?? true)
        
        
        self.diceState = diceState
        
        
        
        let data: Signal<(Data?, TelegramMediaFile), NoError> = context.diceCache.interactiveSymbolData(baseSymbol: baseSymbol, synchronous: approximateSynchronousValue) |> mapToSignal { values in
            for (i, value) in values.enumerated() {
                let str = value.0.withoutColorizer
                
                #if DEBUG
                if getIndex(sideSymbol) == i {
                    return .single((value.1, value.2))
                }
                #endif
                
                if str == sideSymbol {
                    return .single((value.1, value.2))
                }
            }
            return .never()
        }
        
        
        self.playerView.isHidden = true
        self.thumbView.isHidden = false
        
        self.playerView.animation?.triggerOn = nil
        self.playerView.animation?.onFinish = nil
        
        self.loadResourceDisposable.set((data |> deliverOnMainQueue).start(next: { [weak self] data in
            guard let `self` = self else {
                return
            }
            let playPolicy: LottiePlayPolicy
            
            var saveContext: Bool = false
            switch diceState.play {
            case .failed:
                playPolicy = .framesCount(1)
            case .idle:
                playPolicy = .loop
            case let .end(toEndWithAnimation):
                if !toEndWithAnimation || approximateSynchronousValue || self.visibleRect.height == 0 {
                    if self.visibleRect.height == 0 && toEndWithAnimation && !approximateSynchronousValue {
                        let item = self.table?.item(stableId: ChatHistoryEntryId.message(parent))
                        if let item = item, let table = self.table, table.visibleRows().contains(item.index) {
                            playPolicy = .toEnd(from: 0)
                            saveContext = true
                        } else {
                            playPolicy = .toEnd(from: .max)
                            parameters?.markDiceAsPlayed(parent)
                        }
                    } else {
                        playPolicy = .toEnd(from: .max)
                        parameters?.markDiceAsPlayed(parent)
                    }
                    
                } else {
                    saveContext = true
                    playPolicy = .toEnd(from: 0)
                }
                
            }
            if let bytes = data.0 {
                let animation = LottieAnimation(compressed: bytes, key: LottieAnimationEntryKey(key: .media(data.1.id), size: size), cachePurpose: .none, playPolicy: playPolicy, maximumFps: 60)

                animation.onFinish = {
                    if case .end = diceState.play {
                        parameters?.markDiceAsPlayed(parent)
                    }
                }
                switch diceState.play {
                case let .end(animated):
                    if let previous = self.playerView.contextAnimation, animated {
                        switch self.playerView.currentState {
                        case .playing:
                            previous.triggerOn = (.last, { [weak self] in
                                self?.playerView.set(animation, saveContext: saveContext)
                                if animated, let confetti = settings.playConfetti(baseSymbol), confetti.value == currentValue {
                                    animation.triggerOn = (.custom(confetti.playAt), { [weak self] in
                                        if self?.visibleRect.height == self?.frame.height {
                                            PlayConfetti(for: context.window)
                                        }
                                    }, {})
                                }
                            }, { [weak self] in
                                self?.playerView.set(animation)
                            })
                        default:
                            self.playerView.set(animation)
                        }

                    } else {
                        self.playerView.set(animation)
                    }
                default:
                    self.playerView.set(animation)
                }
            } else {
                self.playerView.set(nil)
            }

            self.stateDisposable.set((self.playerView.state |> deliverOnMainQueue).start(next: { [weak self] state in
                guard let `self` = self else { return }
                switch state {
                case .playing:
                    self.playerView.isHidden = false
                    self.thumbView.isHidden = true
                case .initializing, .failed:
                    switch diceState.play {
                    case let .end(animated):
                        if animated {
                            self.playerView.isHidden = false
                            self.thumbView.isHidden = true
                        } else {
                            self.playerView.isHidden = true
                            self.thumbView.isHidden = false
                        }
                    default:
                        self.playerView.isHidden = false
                        self.thumbView.isHidden = true
                    }
                case .stoped, .finished:
                    switch diceState.play {
                    case let .end(animated):
                        if animated {
                            self.playerView.isHidden = false
                            self.thumbView.isHidden = true
                        } else {
                            self.playerView.isHidden = true
                            self.thumbView.isHidden = false
                        }
                    default:
                        self.playerView.isHidden = false
                        self.thumbView.isHidden = false
                    }
                }
            }))
            
            
            let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: size, boundingSize: size, intrinsicInsets: NSEdgeInsets())
            
            self.thumbView.setSignal(signal: cachedMedia(media: data.1, arguments: arguments, scale: self.backingScaleFactor), clearInstantly: true)
            //if !self.thumbView.isFullyLoaded {
            self.thumbView.setSignal(chatMessageDiceSticker(postbox: context.account.postbox, file: data.1, emoji: baseSymbol, value: sideSymbol, scale: self.backingScaleFactor, size: size), cacheImage: { result in
                cacheMedia(result, media: data.1, arguments: arguments, scale: System.backingScale)
            })
            self.thumbView.set(arguments: arguments)
           // }
        }))
       // } else {
            var bp:Int = 0
            bp += 1
      //  }
        
       
        
    }
    
    public override func layout() {
        super.layout()
        self.playerView.frame = bounds
        self.thumbView.frame = bounds
    }
    
}
