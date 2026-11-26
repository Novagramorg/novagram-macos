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

public final class PremiumBoardingDoubleRowItem : GeneralRowItem {
    public let title: TextViewLayout
    public let info: TextViewLayout
    public let itemType: PremiumBoardingDoubleItem
    public let limits: PremiumLimitConfig
    public let presentation: TelegramPresentationTheme
    public init(_ initialSize: NSSize, presentation: TelegramPresentationTheme, limits: PremiumLimitConfig, type: PremiumBoardingDoubleItem) {
        self.itemType = type
        self.limits = limits
        self.presentation = presentation
        self.title = .init(.initialize(string: type.title(limits), color: presentation.colors.text, font: .medium(.title)))
        
        
        let info = NSMutableAttributedString()
        _ = info.append(string: type.info(limits), color: presentation.colors.grayText, font: .normal(.text))
        GeneralRowsHooks.shared.detectLinks(info)
        self.info = .init(info)

        super.init(initialSize, stableId: arc4random64())
        _ = makeSize(initialSize.width)
    }
    
    public override var height: CGFloat {
        return title.layoutSize.height + 4 + info.layoutSize.height + 8 + 30
    }

    public override var accessibilityLabel: String? {
        return title.attributedString.string
    }

    public override var accessibilityValue: String? {
        return info.attributedString.string
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        title.measure(width: width - 50)
        info.measure(width: width - 50)

        return true
    }
    
    public override func viewClass() -> AnyClass {
        return PremiumBoardingDoubleRowView.self
    }
    
}

private final class PremiumBoardingDoubleRowView : TableRowView {
    
    private class LineView: View {
        
        private let normalText = TextView()
        private let normalCount = TextView()

        private let premiumText = TextView()
        private let premiumCount = TextView()

        private let normalBackground = View()
        private let premiumBackground = View(frame: .zero)
        
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(normalBackground)
            addSubview(premiumBackground)
            addSubview(normalText)
            addSubview(premiumText)
            addSubview(premiumCount)
            addSubview(normalCount)
            normalText.userInteractionEnabled = false
            premiumText.userInteractionEnabled = false
            premiumCount.userInteractionEnabled = false
            normalCount.userInteractionEnabled = false
            
            normalText.isSelectable = false
            premiumText.isSelectable = false
            premiumCount.isSelectable = false
            normalCount.isSelectable = false
        }
        
        public func update(_ itemType: PremiumBoardingDoubleItem, presentation: TelegramPresentationTheme, limits: PremiumLimitConfig) {
            let normalLayout = TextViewLayout(.initialize(string: strings().premiumLimitFree, color: presentation.colors.text, font: .medium(13)))
            normalLayout.measure(width: .greatestFiniteMagnitude)
            
            normalText.update(normalLayout)
            
            
            let normalCountLayout = TextViewLayout(.initialize(string: itemType.defaultLimit(limits), color: presentation.colors.text, font: .medium(.text)))
            normalCountLayout.measure(width: .greatestFiniteMagnitude)

            normalCount.update(normalCountLayout)

            
            let premiumCountLayout = TextViewLayout(.initialize(string: itemType.premiumLimit(limits), color: .white, font: .medium(.text)))
            premiumCountLayout.measure(width: .greatestFiniteMagnitude)

            premiumCount.update(premiumCountLayout)
            
            let premiumLayout = TextViewLayout(.initialize(string: strings().premiumLimitPremium, color: .white, font: .medium(.text)))
            premiumLayout.measure(width: .greatestFiniteMagnitude)

            premiumText.update(premiumLayout)

            
            normalBackground.backgroundColor = presentation.colors.grayForeground
            premiumBackground.backgroundColor = itemType.color
            
            needsLayout = true
        }
        
        public override func layout() {
            super.layout()
            let width = frame.width / 2

            
            normalText.centerY(x: 10)
            
            normalCount.centerY(x: frame.midX - 2 - normalCount.frame.width - 10 - 10 - 10)
            
            premiumText.centerY(x: width + 10)
            premiumCount.centerY(x: frame.width - 10 - premiumCount.frame.width)
            
            
            normalBackground.frame = NSMakeRect(0, 0, width, frame.height)
            premiumBackground.frame = NSMakeRect(width, 0, width, frame.height)
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    

    
    private let titleView = TextView()
    private let infoView = TextView()
    private let lineView = LineView(frame: NSMakeRect(0, 0, 0, 30))
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(titleView)
        addSubview(infoView)
        addSubview(lineView)
        titleView.userInteractionEnabled = false
        infoView.userInteractionEnabled = false
        
        titleView.isSelectable = false
        infoView.isSelectable = false
        
        lineView.layer?.cornerRadius = 4
    }
    
    public override func layout() {
        super.layout()
        titleView.setFrameOrigin(NSMakePoint(25, 0))
        infoView.setFrameOrigin(NSMakePoint(25, titleView.frame.maxY + 4))
        lineView.frame = NSMakeRect(20, infoView.frame.maxY + 8, frame.width - 40, 30)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var backdorColor: NSColor {
        guard let item = item as? PremiumBoardingDoubleRowItem else {
            return super.background
        }
        return item.presentation.colors.background
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? PremiumBoardingDoubleRowItem else {
            return
        }
        titleView.update(item.title)
        infoView.update(item.info)
        
        lineView.update(item.itemType, presentation: item.presentation, limits: item.limits)
        
        needsLayout = true

    }
}
