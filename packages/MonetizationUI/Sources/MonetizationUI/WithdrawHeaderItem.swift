import Foundation
import Cocoa
import TelegramCore
import Postbox
import TGUIKit
import SwiftSignalKit
import InputView
import InputTextView
import Localization
import ColorPalette
import TelegramTheme
import TelegramIconsTheme
import TelegramContext
import TelegramUtils
import GeneralRows

final class WithdrawArguments {
    let context: any AccountContextProtocol
    let interactions: TextView_Interactions
    let updateState: (Updated_ChatTextInputState)->Void
    let withdraw:()->Void
    let close:()->Void
    init(context: any AccountContextProtocol, interactions: TextView_Interactions, updateState: @escaping(Updated_ChatTextInputState)->Void, withdraw:@escaping()->Void, close:@escaping()->Void) {
        self.context = context
        self.interactions = interactions
        self.updateState = updateState
        self.withdraw = withdraw
        self.close = close
    }
}

final class WithdrawHeaderItem : GeneralRowItem {
    fileprivate let titleLayout: TextViewLayout
    fileprivate let balance: TextViewLayout
    fileprivate let arguments: WithdrawArguments
    init(_ initialSize: NSSize, stableId: AnyHashable, balance: NSAttributedString, arguments: WithdrawArguments) {
        self.arguments = arguments
        self.titleLayout = .init(.initialize(string: strings().fragmentStarWithdraw, color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1)
        
        self.balance = .init(balance)
        self.balance.measure(width: .greatestFiniteMagnitude)
        
        self.titleLayout.measure(width: initialSize.width - self.balance.layoutSize.width - 40)
        
        super.init(initialSize, height: 50, stableId: stableId)
    }
    
    override func viewClass() -> AnyClass {
        return WithdrawHeaderView.self
    }

    override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    override var accessibilityValue: String? {
        return balance.attributedString.string.replacingOccurrences(of: clown, with: "").trimmingCharacters(in: .whitespaces)
    }
}

private final class WithdrawHeaderView : GeneralRowView {
    private let title = InteractiveTextView()
    private let balance = InteractiveTextView()
    private let dismiss = ImageButton()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(title)
        addSubview(balance)
        addSubview(dismiss)
        
        dismiss.set(handler: { [weak self] _ in
            if let item = self?.item as? WithdrawHeaderItem {
                item.arguments.close()
            }
        }, for: .Click)
    }
    
    override var backdorColor: NSColor {
        return theme.colors.listBackground
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? WithdrawHeaderItem else {
            return
        }
        
        dismiss.set(image: theme.icons.glass_close, for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismiss.autohighlight = false
        dismiss.scaleOnClick = true
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        
        title.set(text: item.titleLayout, context: item.arguments.context)
        balance.set(text: item.balance, context: item.arguments.context)
        
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        
        title.center()
        balance.centerY(x: frame.width - balance.frame.width - 20)
        dismiss.centerY(x: 20)
    }
}
