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
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import TelegramMediaUtils
import TelegramMedia
import LocalAnimations
import CurrencyFormat
import PremiumStatusUI
import SceneEffects
import DustLayer
import InAppPurchaseManager
import ObjcUtils
import PremiumUI
import CalendarUtils
import DateUtils
import LokiRng
import FoundationUtils
import InputView
import InputTextView
import InlineStickerLayer


public final class Fragment_OverviewRowItem : GeneralRowItem {
    
    public struct Overview: Equatable {
        
        public struct Stars : Equatable {
            public let amount: StarsAmount
            public let usdRate: Double
                        
            public var fractional: Double {
                return currencyToFractionalAmount(value: amount.totalValue, currency: XTR) ?? 0
            }
            public var usdAmount: String {
                return "$" + "\(self.fractional * self.usdRate)".prettyCurrencyNumberUsd
            }
            public init(amount: StarsAmount, usdRate: Double) {
                self.amount = amount
                self.usdRate = usdRate
            }
        }
        
        public let amount: Int64
        public let usdAmount: String
        public let info: String
        
        public let stars: Stars?
        public init(amount: Int64, usdAmount: String, info: String, stars: Stars?) {
            self.amount = amount
            self.usdAmount = usdAmount
            self.info = info
            self.stars = stars
        }
    }
    
    public let context: (any AccountContextProtocol)
    
    public let overview: Overview
    
    public let amount: TextViewLayout
    public let info: TextViewLayout
    
    public let currency: LocalTelegramCurrency
    
    public let starsAmount: TextViewLayout?
    
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), overview: Overview, currency: LocalTelegramCurrency, viewType: GeneralViewType) {
        self.context = context
        self.overview = overview
        self.currency = currency
        
                
        let amountAttr = NSMutableAttributedString()
        let justAmount = NSAttributedString.initialize(string: formatCurrencyAmount(overview.amount, currency: currency.rawValue).prettyCurrencyNumber, color: theme.colors.text, font: .medium(.header)).smallDecemial
        amountAttr.append(justAmount)
        amountAttr.append(string: " ≈", color: theme.colors.grayText, font: .normal(.text))
        
        let justAmount2 = NSAttributedString.initialize(string: overview.usdAmount, color: theme.colors.grayText, font: .normal(.text)).smallDecemial
        amountAttr.append(justAmount2)

        self.amount = .init(amountAttr)
        
        self.info = .init(.initialize(string: overview.info, color: theme.colors.grayText, font: .normal(.text)))
        
        if let starsAmount = overview.stars {
            let attr = NSMutableAttributedString()
            attr.append(string: "\(clown) \(starsAmount.amount)", color: theme.colors.text, font: .medium(.text))
            attr.insertEmbedded(.embeddedAnimated(LocalAnimatedSticker.star_currency_new.file), for: clown)
            attr.append(string: " =", color: theme.colors.grayText, font: .normal(.text))
            let usdAmount = NSAttributedString.initialize(string: starsAmount.usdAmount, color: theme.colors.grayText, font: .normal(.text)).smallDecemial
            attr.append(usdAmount)
            self.starsAmount = .init(attr)
        } else {
            self.starsAmount = nil
        }
        
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        amount.measure(width: blockWidth - viewType.innerInset.left - viewType.innerInset.right - 22)
        info.measure(width: blockWidth - viewType.innerInset.left - viewType.innerInset.right)
        starsAmount?.measure(width: blockWidth - viewType.innerInset.left - viewType.innerInset.right - 22)
        return true
    }
    
    public override var accessibilityLabel: String? {
        return info.attributedString.string
    }

    public override var accessibilityValue: String? {
        var parts: [String] = [amount.attributedString.string]
        if let stars = overview.stars {
            parts.append(strings().starListItemCountOther(Int(stars.amount.value)))
        }
        return parts.joined(separator: ", ")
    }

    public override func viewClass() -> AnyClass {
        return OverviewRowView.self
    }
    
    public override var height: CGFloat {
        var height: CGFloat = 0
        height += viewType.innerInset.top
        height += amount.layoutSize.height
        height += 2
        height += info.layoutSize.height
        
        height += viewType.innerInset.bottom
        return height
    }
}

private final class OverviewRowView : GeneralContainableRowView {
    private let amountView = TextView()
    private let infoView = TextView()
    private let icon = StarsHooks.shared.makeStickerView(NSMakeRect(0, 0, 20, 20))

    private var starsAmount: InteractiveTextView?
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(amountView)
        addSubview(infoView)
        addSubview(icon)
        
        amountView.userInteractionEnabled = false
        amountView.isSelectable = false
        
        infoView.userInteractionEnabled = false
        infoView.isSelectable = false
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public override func layout() {
        super.layout()
        guard let item = item as? Fragment_OverviewRowItem else {
            return
        }
        icon.setFrameOrigin(NSMakePoint(item.viewType.innerInset.left, item.viewType.innerInset.top - 3))
        amountView.setFrameOrigin(NSMakePoint(item.viewType.innerInset.left + 22, item.viewType.innerInset.top))
        infoView.setFrameOrigin(NSMakePoint(item.viewType.innerInset.left, amountView.frame.maxY + 2))
        
        if let starsAmount {
            starsAmount.setFrameOrigin(NSMakePoint(amountView.frame.maxX + 20, amountView.frame.minY))
        }
        
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? Fragment_OverviewRowItem else {
            return
        }
        
        (icon as? StarsStickerView)?.updateStarsSticker(file: item.currency.logo.file, size: icon.frame.size, context: item.context, colors: item.currency.colored(theme.colors.accent), playback: .standard, animated: animated)
        
        
        if let starsAmount = item.starsAmount {
            let current: InteractiveTextView
            if let view = self.starsAmount {
                current = view
            } else {
                current = InteractiveTextView(frame: starsAmount.layoutSize.bounds)
                self.starsAmount = current
                addSubview(current)
            }
            current.set(text: starsAmount, context: item.context)
        } else if let view = self.starsAmount {
            performSubviewRemoval(view, animated: animated)
            self.starsAmount = nil
        }
        
        amountView.update(item.amount)
        infoView.update(item.info)
        
        needsLayout = true
    }
}
