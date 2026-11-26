import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import ChatModeTypes
import ChatHistoryModel
import GeneralRows
import LocalAnimations
import TelegramMediaUtils
import TelegramMedia
import AvatarUI
import MessageUtils
import InstantPageUI
import SecureIdUtils
import ColorPalette
import InAppSettings
import FoundationUtils
import ObjcUtils


private final class SaveModalView : View {
    private let imageView: GalleryStickerView = GalleryHooks.shared.makeStickerView()
    private let textView: TextView = TextView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        addSubview(textView)
        self.wantsLayer = true
        self.layer?.cornerRadius = 10.0
        self.autoresizingMask = []
        self.backgroundColor = .blackTransparent
    }
    
    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
    }
    
    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
    
    public override var isFlipped: Bool {
        return true
    }
    
    public override func layout() {
        super.layout()
        
        if !textView.isHidden {
            imageView.centerX(y: 0)
            textView.centerX(y: imageView.frame.maxY - 15)
        } else {
            imageView.centerX(y: 0)
        }
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(animation: LocalAnimatedSticker, size: NSSize, context: any AccountContextProtocol, text: TextViewLayout?) {
        imageView.updateSticker(animation: animation, size: size, context: context)
        textView.isSelectable = false
        textView.isHidden = text == nil
        textView.update(text)
        needsLayout = true
    }
}

private final class BlurModalView : NSVisualEffectView {
    private let imageView: GalleryStickerView = GalleryHooks.shared.makeStickerView()
    private let textView: TextView = TextView()
    public required override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        addSubview(textView)
        self.wantsLayer = true
        self.layer?.cornerRadius = 10.0
        self.autoresizingMask = []
        self.material = .dark
        self.blendingMode = .withinWindow
        self.state = .active
    }
    
    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
    }
    
    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
    
    public override var isFlipped: Bool {
        return true
    }
    
    public override func layout() {
        super.layout()
        
        if !textView.isHidden {
            imageView.centerX(y: 0)
            textView.centerX(y: imageView.frame.maxY - 15)
        } else {
            imageView.centerX(y: 0)
        }
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(animation: LocalAnimatedSticker, size: NSSize, context: any AccountContextProtocol, text: TextViewLayout?) {
        imageView.updateSticker(animation: animation, size: size, context: context)
        textView.isSelectable = false
        textView.isHidden = text == nil
        textView.update(text)
        needsLayout = true
    }
}


public class SaveModalController : ModalViewController {
    public override var background: NSColor {
        return .clear
    }
    
    public override var contentBelowBackground: Bool {
        return true
    }
    
    public override var containerBackground: NSColor {
        return .clear
    }
    
    public override func viewClass() -> AnyClass {
        if false {
            return BlurModalView.self
        } else {
            return SaveModalView.self
        }
    }
    
    public override var redirectMouseAfterClosing: Bool {
        return true
    }
    
    
    public override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        if let view = self.view as? BlurModalView {
            view.update(animation: self.animation, size: NSMakeSize(200, 150), context: self.context, text: self.text)
        } else if let view = self.view as? SaveModalView {
            view.update(animation: self.animation, size: NSMakeSize(200, 150), context: self.context, text: self.text)
        }
        readyOnce()
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    private let animation: LocalAnimatedSticker
    private let text: TextViewLayout?
    private let context: any AccountContextProtocol
    private let shouldBlur: Bool
    public init(_ animation: LocalAnimatedSticker, context: any AccountContextProtocol, shouldBlur: Bool = true, text: TextViewLayout? = nil) {
        self.animation = animation
        self.text = text
        self.context = context
        self.shouldBlur = shouldBlur
        super.init(frame: NSMakeRect(0, 0, 200, 200))
        self.bar = .init(height: 0)
    }
}



public func showSaveModal(for window: Window, context: any AccountContextProtocol, animation: LocalAnimatedSticker, shouldBlur: Bool = true, text: TextViewLayout? = nil, delay _delay: Double) -> Signal<Void, NoError> {
    
    let modal = SaveModalController(animation, context: context, shouldBlur: shouldBlur, text: text)
    
    return Signal<Void, NoError>({ _ -> Disposable in
        showModal(with: modal, for: window, animationType: .scaleCenter)
        return ActionDisposable {
            modal.close()
        }
    }) |> timeout(_delay, queue: Queue.mainQueue(), alternate: Signal<Void, NoError>({ subscriber -> Disposable in
        modal.close()
        subscriber.putCompletion()
        return EmptyDisposable
    }))
}
