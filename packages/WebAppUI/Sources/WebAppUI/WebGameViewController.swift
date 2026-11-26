import Cocoa
import TelegramMediaUtils
import Foundation
import WebKit
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import FoundationUtils
import ObjcUtils
import KeyboardKey
import TelegramIconsTheme
import TelegramMedia
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import LocalAnimations
import FilePanels
import TelegramLinks
import PremiumStatusUI
import SystemPermissions
import Svg
import LocalAuthentication

public final class GameView : View {
    
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.webView.isHidden = window == nil
    }
    
    public let headerView: WebpageHeaderView
    
    public let webView: WKWebView
    public let isBrowser: Bool
    
    public required init(frame frameRect: NSRect, configuration: WKWebViewConfiguration!, isBrowser: Bool) {
        self.isBrowser = isBrowser
        headerView = .init(frame: NSMakeRect(0, 0, frameRect.width, 50))
        webView = WKWebView(frame: CGRect(origin: NSMakePoint(0, headerView.frame.height), size: NSMakeSize(frameRect.width, frameRect.height - headerView.frame.height)), configuration: configuration)
        super.init(frame: frameRect)
        
        addSubview(webView)
        addSubview(headerView)
        
        headerView.isHidden = isBrowser

        updateLocalizationAndTheme(theme: theme)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: headerView, frame: NSMakeRect(0, headerView.isHidden ? -50 : 0, size.width, 50))
        transition.updateFrame(view: webView, frame: NSMakeRect(0, headerView.frame.maxY, size.width, size.height - headerView.frame.maxY))
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        
        self.headerView.backgroundColor = theme.colors.background
    }
}

private struct PageState : Equatable {
    public var title: String = ""
    public var subtitle: String = ""
    public var peer: EnginePeer?
}

public class WebGameViewController: ModalViewController, WKUIDelegate, BrowserPage {
    
    private let statePromise = ValuePromise<PageState>(ignoreRepeated: true)
    private let stateValue = Atomic(value: PageState())
    private func updateState(_ f:(PageState)->PageState) -> Void {
        self.statePromise.set(self.stateValue.modify(f))
    }
    
    
    public func contextMenu() -> ContextMenu {
        let menu = ContextMenu()
        menu.addItem(ContextMenuItem(strings().modalShare, handler: { [weak self] in
            self?.share_game("")
        }, itemImage: MenuAnimation.menu_share.value))
        return menu
    }
    
    public func backButtonPressed() {
        
    }
    
    public func reloadPage() {
        self.webView.reload()
    }
    
    public var externalState: Signal<WebpageModalState, NoError> {
        return statePromise.get() |> map {
            return .init(title: $0.title, subtitle: $0.subtitle, peer: $0.peer)
        }
    }
    
    public func add(_ tab: BrowserTabData.Data) -> Bool {
        return false
    }
    
    private let gameUrl:String
    public let peerId:PeerId
    private let context: (any AccountContextProtocol)
    
    private var media:TelegramMediaGame!
    private var peer:Peer!
    private var threadId: Int64?
    
    private let messageId:MessageId
    private let loadMessageDisposable = MetaDisposable()
    private let browser: BrowserLinkManager
    public init(_ context: (any AccountContextProtocol), peerId:PeerId, messageId:MessageId, gameUrl:String, browser: BrowserLinkManager) {
        self.gameUrl = gameUrl
        self.peerId = peerId
        self.context = context
        self.messageId = messageId
        self.browser = browser
        super.init()
    }
    
    public override var enableBack: Bool {
        return true
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        loadMessageDisposable.set((context.account.postbox.messageAtId(messageId) |> deliverOnMainQueue).start(next: { [weak self] message in
            if let message = message, let game = message.anyMedia as? TelegramMediaGame {
                self?.start(with: game, peer: message.inlinePeer, threadId: message.threadId)
            }
        }))
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.genericView.updateLocalizationAndTheme(theme: theme)
    }
    
    public func start(with game: TelegramMediaGame, peer: Peer?, threadId: Int64?) {
        self.media = game
        self.peer = peer
        self.threadId = threadId
        
        updateState { current in
            var current = current
            current.subtitle = media.name
            current.title = peer?.displayTitle ??  media.title
            if let peer = peer {
                current.peer = .init(peer)
            }
            return current
        }
        
        genericView.headerView.update(title: peer?.displayTitle ?? media.title, subtitle: media.name, left: .dismiss, animated: false, leftCallback: { [weak self] in
            self?.close()
        }, contextMenu: { [weak self] in
            let menu = ContextMenu()
            menu.addItem(ContextMenuItem(strings().modalShare, handler: {
                self?.share_game("")
            }, itemImage: MenuAnimation.menu_share.value))
            return menu
        }, context: context, bot: peer)
                
        if let url = URL(string:gameUrl) {
            webView.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15))
        }
        
        
        readyOnce()
    }
    
    
    public override func close(animationType: ModalAnimationCloseBehaviour = .common) {        
        browser.close(confirm: false)
    }
    
    
    public override func initializer() -> GameView {
        
        let js = "var TelegramWebviewProxyProto = function() {}; " +
            "TelegramWebviewProxyProto.prototype.postEvent = function(eventName, eventData) { " +
            "window.webkit.messageHandlers.performAction.postMessage({'eventName': eventName, 'eventData': eventData}); " +
            "}; " +
        "var TelegramWebviewProxy = new TelegramWebviewProxyProto();"
        
        let configuration = WKWebViewConfiguration()
        
        if FastSettings.debugWebApp {
            configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        }
        
        let userController = WKUserContentController()
        
        let userScript = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userController.addUserScript(userScript)
        
        userController.add(WeakScriptMessageHandler { [weak self] message in
            if let strongSelf = self {
                strongSelf.handleScriptMessage(message)
            }
        }, name: "performAction")
        
        
        configuration.userContentController = userController
        
        let rect = NSMakeRect(_frameRect.minX, _frameRect.minY, _frameRect.width, _frameRect.height - bar.height)
        
        return GameView(frame: rect, configuration: configuration, isBrowser: true)
    }
    
    private func handleScriptMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else {
            return
        }
        guard message.frameInfo.isMainFrame else {
            return
        }
        
        guard let eventName = body["eventName"] as? String else {
            return
        }
        
        switch eventName {
        case "share_game":
            self.share_game("")
        case "share_score":
            self.share_score("")
        case "game_over":
            self.game_over("")
        case "game_loaded":
            self.game_loaded("")
        default:
            break
        }
    }


    
    @objc public func game_loaded(_ data:String) {
        
    }
    @objc public func game_over(_ data:String) {
        
    }
    @objc public func share_game(_ data:String) {
        if let window {
            BrowserHooks.shared.shareLink(context, context.meUrlPrefix + "\(self.peer.addressName ?? "gamebot")" + "?game=\(self.media.name)", window)
        }
    }
    @objc public func share_score(_ data:String) {
        
        let context = self.context
        let messageId = self.messageId
        let threadId = self.threadId
        if let window {
            BrowserHooks.shared.shareViaCallback(context, window, { peerIds in
                let signals = peerIds.map { context.engine.messages.forwardGameWithScore(messageId: messageId, to: $0, threadId: threadId, as: nil) }
                _ = combineLatest(signals).startStandalone()
            })
        }
    }
    
    private var webView: WKWebView {
        return (self.view as! GameView).webView
    }
    
    private var genericView: GameView {
        return (self.view as! GameView)
    }
    
    
    
    public override func viewClass() -> AnyClass {
        return GameView.self
    }
    
    public override func becomeFirstResponder() -> Bool? {
        return true
    }
    
    public override func firstResponder() -> NSResponder? {
        return webView
    }
    
    public override func backKeyAction() -> KeyHandlerResult {
        return .invokeNext
    }
    
    deinit {
        genericView.webView.stopLoading()
        genericView.webView.loadHTMLString("", baseURL: nil)
        genericView.webView.removeFromSuperview()
    }
    
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        window?.set(escape: { [weak self] _ -> KeyHandlerResult in
            if self?.escapeKeyAction() == .rejected {
                self?.close()
            }
            return .invoked
        }, with: self, priority: responderPriority)
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.window?.removeAllHandlers(for: self)
    }
    public override func measure(size: NSSize) {
        let s = NSMakeSize(size.width + 20, size.height + 20)
        let size = NSMakeSize(420, min(420 + 420 * 0.6, s.height - 80))
        let rect = size.bounds.insetBy(dx: 10, dy: 10)
        self.genericView.frame = rect
        self.genericView.updateLayout(size: rect.size, transition: .immediate)
    }

    
}
