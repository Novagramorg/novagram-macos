import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import TelegramMediaUtils
import SecureIdUtils
import TelegramLinks
import PhoneNumberUtils
import KeyboardKey
import TGPassportMRZ
import OCR
import FilePanels
import ObjcUtils

class PassportAcceptRowItem: GeneralRowItem {

    init(_ initialSize: NSSize, stableId: AnyHashable, enabled: Bool, action:@escaping()->Void) {
        super.init(initialSize, height: 50, stableId: stableId, action: action, enabled: enabled)
    }
    
    
    override func viewClass() -> AnyClass {
        return PassportAcceptRowView.self
    }

    override var accessibilityLabel: String? {
        return strings().secureIdRequestAccept
    }
}

final class PassportAcceptRowView : TableRowView {
    private let button: TextButton = TextButton()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(button)
        button.set(font: .medium(.header), for: .Normal)
        
        button.set(handler: { [weak self] _ in
            guard let item = self?.item as? GeneralRowItem else {return}
            item.action()
        }, for: .Click)
    }
    
    override func layout() {
        super.layout()
        guard item is GeneralRowItem else {return}
        
        _ = button.sizeToFit(NSZeroSize, NSMakeSize(170, 40), thatFit: true)
        button.center()
        button.layer?.cornerRadius = 20
    }
    
    override func updateColors() {
        super.updateColors()
        button.set(text: strings().secureIdRequestAccept, for: .Normal)
        button.set(color: .white, for: .Normal)
    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? GeneralRowItem else {return}

      //  button.userInteractionEnabled = item.enabled
        button.autohighlight = false
        button.set(background: item.enabled ? theme.colors.accent : theme.colors.grayForeground, for: .Normal)
        button.set(image: theme.icons.secureIdAuth, for: .Normal)
        needsLayout = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
