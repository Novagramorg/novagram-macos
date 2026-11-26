import Cocoa
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


public class ContextInlineWebViewRowItem: TableRowItem {
    fileprivate let account:Account
    fileprivate let layout:TextViewLayout
    fileprivate let callback:()->Void
    public init(_ initialSize:NSSize, text: String, url: String, account:Account, callback:@escaping()->Void) {
        self.account = account
        self.callback = callback
        layout = TextViewLayout(.initialize(string: text, color: theme.colors.link, font: .normal(.text)), maximumNumberOfLines: 1, truncationType: .end)
        layout.measure(width: initialSize.width - 40)
        super.init(initialSize)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        layout.measure(width: width - 40)
        return success
    }
    
    public override func viewClass() -> AnyClass {
        return ContextInlineWebViewRowView.self
    }
    
    public override var height: CGFloat {
        return 40
    }

    public override var accessibilityLabel: String? {
        return layout.attributedString.string
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func accessibilityPerformPress() -> Bool {
        callback()
        return true
    }
    
}

public class ContextInlineWebViewRowView: TableRowView {
    private let textView:TextView = TextView()
    private let overlay:OverlayControl = OverlayControl()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        addSubview(overlay)
        overlay.addSubview(textView)
        
        overlay.scaleOnClick = true
        
        textView.backgroundColor = theme.colors.background
        overlay.set(handler: { [weak self] _ in
            if let item = self?.item as? ContextInlineWebViewRowItem {
                item.callback()
            }
        }, for: .Click)
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        needsDisplay = true
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        if let item = item as? ContextInlineWebViewRowItem {
            overlay.setFrameSize(frame.size)
            textView.update(item.layout)
            textView.center()
        }
    }
    
    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        
        if let item = item, let table = item.table {
            if item.index != table.count - 1 {
                ctx.setFillColor(theme.colors.border.cgColor)
                ctx.fill(NSMakeRect(0, frame.height - .borderSize, frame.width, .borderSize))
            }
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}



