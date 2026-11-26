import Cocoa
import Localization
import TelegramUtils
import TelegramMediaUtils
import TelegramTheme
import TelegramCore
import SwiftSignalKit
import RangeSet

import TGUIKit
import TelegramContext
import AudioPlayerCore
import WebKit

private final class InstantPageWebView : WKWebView {
    
    public var enableScrolling: Bool = true
    
    public override func scrollWheel(with event: NSEvent) {
        if enableScrolling {
            super.scrollWheel(with: event)
        } else {
            if event.scrollingDeltaX != 0 {
                super.scrollWheel(with: event)
            } else {
                super.enclosingScrollView?.scrollWheel(with: event)
            }
        }
    }
}


public final class InstantPageWebEmbedView: View, InstantPageView {
    public let url: String?
    public let html: String?
    
    private var webView: InstantPageWebView!
    public let updateWebEmbedHeight: (CGFloat) -> Void
    public init(frame: CGRect, url: String?, html: String?, enableScrolling: Bool, updateWebEmbedHeight: @escaping(CGFloat) -> Void) {
        self.url = url
        self.html = html
        self.updateWebEmbedHeight = updateWebEmbedHeight
        super.init()
        

        
        let js = "var TelegramWebviewProxyProto = function() {}; " +
            "TelegramWebviewProxyProto.prototype.postEvent = function(eventName, eventData) { " +
            "window.webkit.messageHandlers.performAction.postMessage({'eventName': eventName, 'eventData': eventData}); " +
            "}; " +
        "var TelegramWebviewProxy = new TelegramWebviewProxyProto();"
        
        let configuration = WKWebViewConfiguration()
        let userController = WKUserContentController()
        
        let userScript = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userController.addUserScript(userScript)
        
        userController.add(WeakScriptMessageHandler { [weak self] message in
            if let strongSelf = self {
                strongSelf.handleScriptMessage(message)
            }
        }, name: "performAction")
        
        configuration.userContentController = userController
        
        let webView = InstantPageWebView(frame: CGRect(origin: CGPoint(), size: frame.size), configuration: configuration)

        
        
        if let html = html {
            webView.loadHTMLString(html, baseURL: nil)
        } else if let url = url, let parsedUrl = URL(string: url) {
            var request = URLRequest(url: parsedUrl)
            if let scheme = parsedUrl.scheme, let host = parsedUrl.host {
                let referrer = "\(scheme)://\(host)"
                request.setValue(referrer, forHTTPHeaderField: "Referer")
            }
            webView.load(request)
        }
        self.webView = webView
        webView.enableScrolling = enableScrolling
        addSubview(webView)
    }
    
    private func handleScriptMessage(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else {
            return
        }
        guard message.frameInfo.isMainFrame else {
            return
        }
        
        guard let eventName = body["eventName"] as? String, let eventString = body["eventData"] as? String else {
            return
        }
        
        guard let eventData = eventString.data(using: .utf8) else {
            return
        }
        
        guard let dict = (try? JSONSerialization.jsonObject(with: eventData, options: [])) as? [String: Any] else {
            return
        }
        
        if eventName == "resize_frame", let height = dict["height"] as? Int {
            self.updateWebEmbedHeight(CGFloat(height))
        }
    }
    
    deinit {
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        
        self.webView.frame = self.bounds
    }
    
    public func updateIsVisible(_ isVisible: Bool) {
    }
}
