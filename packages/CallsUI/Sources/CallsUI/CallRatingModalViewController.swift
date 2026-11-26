import Cocoa
import TGUIKit
import TelegramCore

import SwiftSignalKit
import Postbox
import TelegramCallsCore
import TelegramTheme
import Localization
import TelegramContext
import GeneralRows
import InputDataUI
import ColorPalette



private enum CallRatingState {
    case stars
}

private class CallRatingModalView: View {
    public let rating:View = View()
    public let textView = TextView()
    public var starsChangeHandler:((Int32?)->Void)? = nil
    private(set) var stars:Int32? = nil
    public var state:CallRatingState = .stars {
        didSet {
            if oldValue != state {
                updateState(state, animated: true)
            }
        }
    }
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        var x:CGFloat = 0
        for i in 0 ..< 5 {
            let star = ImageButton()
            star.setAccessibilityLabel(strings().voiceOverCallsRatingStarsOther(i + 1))
            star.set(image: TelegramThemeHooks.shared.image(.iconCallStar).precomposed(theme.colors.accent), for: .Normal)
            star.sizeToFit()
            star.setFrameOrigin(x, 0)
            rating.addSubview(star)
            x += floorToScreenPixels(backingScaleFactor, star.frame.width) + 10
            
            star.set(handler: { [weak self] current in
                for j in 0 ... i {
                    (self?.rating.subviews[j] as? ImageButton)?.set(image: TelegramThemeHooks.shared.image(.iconCallStarHighlighted).precomposed(theme.colors.accent), for: .Normal)
                }
                for j in i + 1 ..< 5 {
                    (self?.rating.subviews[j] as? ImageButton)?.set(image: TelegramThemeHooks.shared.image(.iconCallStar).precomposed(theme.colors.accent), for: .Normal)
                }
                self?.state = .stars
                delay(0.15, closure: {
                    self?.starsChangeHandler?( Int32(i + 1) )
                })
            }, for: .Click)
        }
        rating.setFrameSize(x - 10, floorToScreenPixels(backingScaleFactor, rating.subviews[0].frame.height))
        addSubview(rating)
        addSubview(textView)
        
        textView.isSelectable = false
        textView.userInteractionEnabled = false
        
        updateState(.stars)
        
        let layout = TextViewLayout(.initialize(string: strings().callRatingModalText, color: theme.colors.text, font: .medium(.text)), alignment: .center)
        layout.measure(width: frame.width - 60)
        
        textView.update(layout)
        
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        rating.centerX(y: frame.midY + 5)
        textView.centerX(y: frame.midY - textView.frame.height - 5)
    }
    
    private func updateState(_ state:CallRatingState, animated: Bool = false) {
        switch state {
        case .stars:
            rating.change(pos: focus(rating.frame.size).origin, animated: animated)
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

public class CallRatingModalViewController: ModalViewController {
    
    private let context:any AccountContextProtocol
    private let callId:CallId
    private var starsCount:Int32? = nil
    private let isVideo: Bool
    private let userInitiated: Bool
    public init(_ context: any AccountContextProtocol, callId:CallId, userInitiated: Bool, isVideo: Bool) {
        self.context = context
        self.callId = callId
        self.isVideo = isVideo
        self.userInitiated = userInitiated
        super.init(frame: NSMakeRect(0, 0, 300, 100))
        bar = .init(height: 0)
    }
    
    private var genericView:CallRatingModalView {
        return view as! CallRatingModalView
    }
    
    
    public override func viewClass() -> AnyClass {
        return CallRatingModalView.self
    }
    
    public override var modalInteractions: ModalInteractions? {
        return ModalInteractions(acceptTitle: strings().callRatingModalNotNow, singleButton: true)
    }
    

    public override func becomeFirstResponder() -> Bool? {
        return true
    }

    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        genericView.starsChangeHandler = { [weak self] stars in
            if let stars = stars {
                self?.saveRating(Int(stars))
            }
        }
        readyOnce()
    }
    
    private func saveRating(_ starsCount: Int) {
        self.close()
        if starsCount < 4, let window = self.window {
            showModal(with: PhoneCallUIHooks.shared.makeCallFeedbackController(context, callId, starsCount, userInitiated, isVideo), for: window)
        } else {
            let _ = rateCallAndSendLogs(context: context, callId: self.callId, starsCount: starsCount, comment: "", userInitiated: userInitiated, includeLogs: false).start()
        }
    }
}


public func rateCallAndSendLogs(context: any AccountContextProtocol, callId: CallId, starsCount: Int, comment: String, userInitiated: Bool, includeLogs: Bool) -> Signal<Void, NoError> {
    let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(4244000))
    
    let rate = context.engine.calls.rateCall(callId: callId, starsCount: Int32(starsCount), comment: comment, userInitiated: userInitiated)
    if includeLogs {
        let id = arc4random64()
        let name = "\(callId.id)_\(callId.accessHash).log.json"
        let path = callLogsPath(account: context.account) + "/" + name
        let file = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil, resource: LocalFileReferenceMediaResource(localFilePath: path, randomId: id), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/text", size: nil, attributes: [.FileName(fileName: name)], alternativeRepresentations: [])
        let message = EnqueueMessage.message(text: comment, attributes: [], inlineStickers: [:], mediaReference: .standalone(media: file), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
        return rate
            |> then(enqueueMessages(account: context.account, peerId: peerId, messages: [message])
                |> mapToSignal({ _ -> Signal<Void, NoError> in
                    return .single(Void())
                }))
    } else if !comment.isEmpty {
        return rate
        |> then(enqueueMessages(account: context.account, peerId: peerId, messages: [.message(text: comment, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])])
                |> mapToSignal({ _ -> Signal<Void, NoError> in
                    return .single(Void())
                }))
    } else {
        return rate
    }
}
