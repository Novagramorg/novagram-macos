import Foundation
import AppKit
import TGUIKit
import TelegramContext

final class Avatar_StickersList : View {
    private var stickersView: NSView?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func set(view: NSView, context: any AccountContextProtocol, animated: Bool) {
        self.stickersView = view
        self.addSubview(view)
        
        needsLayout = true
    }
    override func layout() {
        super.layout()
        self.stickersView?.frame = bounds
    }
}


