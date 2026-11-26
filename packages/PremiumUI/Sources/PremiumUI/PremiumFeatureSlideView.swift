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

public protocol PremiumSlideView {
    func willAppear()
    func willDisappear()
}

extension PremiumDemoLegacyPhoneView : PremiumSlideView {
    public func willAppear() {
    }
    public func willDisappear() {
    }
}



extension ReactionCarouselView : PremiumSlideView {
    public func willAppear() {
        self.animateIn()
    }
    public func willDisappear() {
        self.animateOut()
    }
}

extension PremiumStickersDemoView : PremiumSlideView {
    public func willAppear() {
    }
    public func willDisappear() {
    }
}

public final class PremiumFeatureSlideView : View, SlideViewProtocol {
    private let nameView: TextView = TextView()
    private let descView: TextView = TextView()
    private let bottom = View()
    private let content = View()
    
    private var view: (NSView & PremiumSlideView)?
    private var getView: ((PremiumFeatureSlideView)->(NSView & PremiumSlideView)?)?
    
    private var decorationView: (NSView & PremiumDecorationProtocol)?

    public enum BackgroundDecoration {
        case none
        case dataRain
        case swirlStars
        case fasterStars
        case badgeStars
        case hello
    }
    private var bgDecoration: BackgroundDecoration = .none

    private let presentation: TelegramPresentationTheme

    public init(frame frameRect: NSRect, presentation: TelegramPresentationTheme) {
        self.presentation = presentation
        super.init(frame: frameRect)
        bottom.addSubview(descView)
        bottom.addSubview(nameView)
        
        descView.userInteractionEnabled = false
        descView.isSelectable = false
        
        nameView.userInteractionEnabled = false
        nameView.isSelectable = false
        
        addSubview(bottom)
        addSubview(content)
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public var appear: (()->Void)? = nil
    public var disappear: (()->Void)? = nil

    public func setup(context: (any AccountContextProtocol), type: PremiumValue, decoration: BackgroundDecoration, getView: @escaping(PremiumFeatureSlideView)->(NSView & PremiumSlideView)) {
        
        self.getView = getView
        self.bgDecoration = decoration
        
        let title = type.title(context.premiumLimits)
        let info = type.info(context.premiumLimits)
        
        let titleLayout = TextViewLayout(.initialize(string: title, color: presentation.colors.text, font: .medium(.title)), alignment: .center)
        let infoLayout = TextViewLayout(.initialize(string: info, color: presentation.colors.text, font: .normal(.text)), alignment: .center)
        
        
        titleLayout.measure(width: frame.width - 40)
        infoLayout.measure(width: frame.width - 40)
        
        nameView.update(titleLayout)
        descView.update(infoLayout)
        
        needsLayout = true
    }
    
    public var decoration: PremiumDecorationProtocol? {
        return self.decorationView
    }
    
    
    public func willAppear() {
        if self.view == nil {
            self.view = self.getView?(self)
        }
        guard let view = self.view else {
            return
        }
        view.willAppear()
        view.frame = bounds
        self.content.addSubview(view)
        
        appear?()
        
        switch bgDecoration {
        case .none:
            if let decorationView = decorationView {
                self.decorationView = decorationView
                performSubviewRemoval(decorationView, animated: true)
            }
        case .dataRain:
            let current: (NSView & PremiumDecorationProtocol)
            if let view = self.decorationView {
                current = view
            } else {
                current = DataRainView() ?? SwirlStarsView(frame: content.bounds)
                self.decorationView = current
                content.addSubview(current, positioned: .below, relativeTo: content.subviews.first)
            }
            current.setVisible(true)
        case .swirlStars:
            let current: (NSView & PremiumDecorationProtocol)
            if let view = self.decorationView {
                current = view
            } else {
                current = SwirlStarsView(frame: content.bounds)
                self.decorationView = current
                content.addSubview(current, positioned: .below, relativeTo: content.subviews.first)
            }
            current.setVisible(true)
        case .fasterStars:
            let current: (NSView & PremiumDecorationProtocol)
            if let view = self.decorationView {
                current = view
            } else {
                current = FasterStarsView(frame: content.bounds)
                self.decorationView = current
                content.addSubview(current, positioned: .below, relativeTo: content.subviews.first)
            }
            current.setVisible(true)
        case .badgeStars:
            let current: (NSView & PremiumDecorationProtocol)
            if let view = self.decorationView {
                current = view
            } else {
                current = BadgeStarsView(frame: content.bounds)
                self.decorationView = current
                content.addSubview(current, positioned: .below, relativeTo: content.subviews.first)
            }
            current.setVisible(true)
        case .hello:
            let current: (NSView & PremiumDecorationProtocol)
            if let view = self.decorationView {
                current = view
            } else {
                current = HelloView(frame: content.bounds)
                self.decorationView = current
                content.addSubview(current, positioned: .below, relativeTo: content.subviews.first)
            }
            current.setVisible(true)
        }
        
        needsLayout = true
    }
    
    public func willDisappear() {
        disappear?()
        self.decorationView?.setVisible(false)
        self.view?.willDisappear()
    }
    
    deinit {
        var bp = 0
        bp += 1
    }
    
    public override func layout() {
        super.layout()
        
        content.frame = NSMakeRect(0, 0, frame.width, frame.height - 114)
        bottom.frame = NSMakeRect(0, content.frame.height, frame.width, frame.height - content.frame.height)
        
        for subview in content.subviews {
            subview.frame = content.bounds
        }
        
        nameView.centerX(y: 20)
        descView.centerX(y: nameView.frame.maxY + 10)

    }
}
