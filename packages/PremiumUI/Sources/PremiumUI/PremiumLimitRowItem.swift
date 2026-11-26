import Cocoa
import Foundation
import TGUIKit
import TelegramMedia
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import LocalAnimations
import CurrencyFormat
import SceneEffects
import InAppPurchaseManager
import InlineStickers
import ObjcUtils

public final class PremiumIncreaseLimitItem : GeneralRowItem {
    public let limitType: PremiumLimitController.LimitType
    public let counts: PremiumLimitController.Counts?
    public let context: (any AccountContextProtocol)
    public var updatedHeight: CGFloat = 271
    public let callback: ()->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), type: PremiumLimitController.LimitType, counts: PremiumLimitController.Counts?, viewType: GeneralViewType, callback:@escaping()->Void) {
        self.limitType = type
        self.counts = counts
        self.context = context
        self.callback = callback
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        return true
    }
    
    public override var height: CGFloat {
        return updatedHeight
    }

    public override var accessibilityLabel: String? {
        return limitType.titleText
    }
    
    public override func viewClass() -> AnyClass {
        return PremiumIncreaseLimitView.self
    }
}


private final class PremiumIncreaseLimitView: GeneralContainableRowView {
    private let view = PremiumLimitView(frame: NSMakeRect(0, 0, 350, 200))
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(view)
    }
    
    public override func layout() {
        super.layout()
        view.frame = containerView.bounds
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? PremiumIncreaseLimitItem else {
            return
        }
        
        view.premium = item.callback
        
        let size = view.update(with: item.limitType, counts: item.counts, context: item.context, animated: animated, hasDismiss: false)

        if item.updatedHeight != size.height {
            item.updatedHeight = size.height
            item.noteHeightOfRow()
        }
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

