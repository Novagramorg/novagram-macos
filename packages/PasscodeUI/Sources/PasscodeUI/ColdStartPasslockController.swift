import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import AlertsUI
import SystemPermissions
import BuildConfig
import LocalAuthentication
import InputDataUI
import GeneralRows


public class ColdStartPasslockController: ModalViewController {
    private let valueDisposable = MetaDisposable()
    private let logoutDisposable = MetaDisposable()

    private let logoutImpl:() -> Signal<Never, NoError>
    private let checkNextValue: (String)->Bool
    public init(checkNextValue:@escaping(String)->Bool, logoutImpl:@escaping()->Signal<Never, NoError>) {
        self.checkNextValue = checkNextValue
        self.logoutImpl = logoutImpl
        super.init(frame: NSMakeRect(0, 0, 350, 350))
        self.bar = .init(height: 0)
    }
    
    public override var isVisualEffectBackground: Bool {
        return false
    }
    
    public override var isFullScreen: Bool {
        return true
    }
    
    public override var background: NSColor {
        return self.containerBackground
    }
    
    private var genericView:PasscodeLockView {
        return self.view as! PasscodeLockView
    }
    
   
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        
        genericView.logoutImpl = { [weak self] in
            guard let window = self?.window else { return }
            
            verifyAlert_button(for: window, information: strings().accountConfirmLogoutText, successHandler: { [weak self] _ in
                guard let `self` = self else { return }
                
                _ = showModalProgress(signal: self.logoutImpl(), for: window).start(completed: { [weak self] in
                    delay(0.2, closure: { [weak self] in
                        self?.close()
                    })
                })
            })
        }
        
        var locked = false
        
        valueDisposable.set((genericView.value.get() |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let `self` = self, !locked else {
                return
            }
            if !self.checkNextValue(value) {
                self.genericView.input.shake()
            } else {
                locked = true
            }
        }))
        
        genericView.update(hasTouchId: false)
        readyOnce()
        
        
    }
    
    public override var closable: Bool {
        return false
    }
    
    
    public override func escapeKeyAction() -> KeyHandlerResult {
        return .invoked
    }
    
    public override func firstResponder() -> NSResponder? {
        if !(window?.firstResponder is NSText) {
            return genericView.input
        }
        let editor = self.window?.fieldEditor(true, for: genericView.input)
        if window?.firstResponder != editor {
            return genericView.input
        }
        return editor
        
    }
    
    public override var containerBackground: NSColor {
        return theme.colors.background.withAlphaComponent(1.0)
    }
    public override var handleEvents: Bool {
        return true
    }
    
    public override var cornerRadius: CGFloat {
        return 0
    }
    
    public override var handleAllEvents: Bool {
        return true
    }
    
    
    public override var responderPriority: HandlerPriority {
        return .supreme
    }
    
    deinit {
        logoutDisposable.dispose()
        valueDisposable.dispose()
        self.window?.removeAllHandlers(for: self)
    }
    
    public override func viewClass() -> AnyClass {
        return PasscodeLockView.self
    }
    
}

