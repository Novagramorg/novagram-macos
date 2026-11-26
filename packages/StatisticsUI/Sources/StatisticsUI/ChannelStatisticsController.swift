import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore

import WebKit
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import AvatarUI
import ShortPeerRow
import LocalAnimations
import GraphUI
import DateUtils
import TelegramIconsTheme
import TelegramMediaUtils
import MessageTextUtils



open class ChannelStatisticsController<Context: AccountContextProtocol>: TelegramGenericViewController<WebView, Context> {
    private let peerId:PeerId
    
    private let disposable = MetaDisposable()
    private let statsUrl: String
    public init(_ context: Context, _ peerId: PeerId, statsUrl: String) {
        self.peerId = peerId
        self.statsUrl = statsUrl
        super.init(context)
        load(with: statsUrl)
    }
    
    open override var enableBack: Bool {
        return true
    }


    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        genericView.mainFrame.load(URLRequest(url: URL(string:"file://blank")!))
        genericView.mainFrame.stopLoading()
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        genericView.wantsLayer = true
        readyOnce()
    }
    
    private func load(with url: String) {
        
        if let url = URL(string:url) {
            genericView.mainFrame.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15))
        }
        
    }
    
    
    
    open override func becomeFirstResponder() -> Bool? {
        return true
    }
    
    open override func firstResponder() -> NSResponder? {
        return genericView
    }
    
    open override func backKeyAction() -> KeyHandlerResult {
        return .invokeNext
    }
    
    deinit {
        disposable.dispose()
    }
    
}
