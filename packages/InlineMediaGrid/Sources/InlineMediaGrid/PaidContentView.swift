import Cocoa
import SwiftSignalKit
import Postbox
import TelegramCore
import TGUIKit
import TelegramContext
import TelegramUtils
import GeneralRows
import LocalAnimations
import InlineStickerLayer

public final class PaidContentView: NSVisualEffectView {
    private let textView = InteractiveTextView()
    public required override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.material = .ultraDark
        self.blendingMode = .withinWindow
        self.state = .active
        
        addSubview(textView)
        
        textView.userInteractionEnabled = false
        textView.textView.isSelectable = false
        
    }
    
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(amount: Int64, context: any AccountContextProtocol, short: Bool) {
        
        let attr = NSMutableAttributedString()
        attr.append(string: "\(clown)", color: .white, font: .medium(.text))
        attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)
        attr.append(string: " \(amount)", color: .white, font: .medium(.text))
        
        let textLayout = TextViewLayout(attr)
        textLayout.measure(width: .greatestFiniteMagnitude)

        self.textView.set(text: textLayout, context: context)
        
        self.setFrameSize(NSMakeSize(textView.frame.width + 20, 30))

    }
    
    public override func layout() {
        super.layout()
        self.textView.centerY(x: 10)
    }
}
