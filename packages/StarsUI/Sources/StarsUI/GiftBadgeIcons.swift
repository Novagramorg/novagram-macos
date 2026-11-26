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

public func generateGiftBadgeBackground(background: CGImage, text: String, textColor: NSColor = NSColor.white) -> CGImage {
    let textImage = generateGiftBadgeText(size: background.systemSize, text: text, textColor: textColor)
    return generateImage(background.systemSize, contextGenerator: { size, ctx in
        ctx.clear(CGRect(origin: .zero, size: size))
        ctx.draw(background, in: size.bounds)
        ctx.draw(textImage, in: size.bounds)
    })!
}

public func generateTextIcon_NewBadge_Flipped(bgColor: NSColor, textColor: NSColor) -> CGImage {
    let image = generateTextIcon_AccentBadge(text: strings().badgeNew, bgColor: bgColor, textColor: textColor)
    return generateImage(image.systemSize, rotatedContext: { size, ctx in
        ctx.clear(size.bounds)
        ctx.draw(image, in: image.systemSize.bounds)
    })!
}


public func generateGiftBadgeText(size: NSSize, text: String, textColor: NSColor = NSColor.white) -> CGImage {
    let textNode = TextNode.layoutText(.initialize(string: text, color: textColor, font: .bold(.small)), nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, 20), nil, false, .center)
    return generateImage(size, rotatedContext: { size, ctx in
        ctx.clear(CGRect(origin: .zero, size: size))
        ctx.saveGState()
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.rotate(by: CGFloat.pi / 4)
        ctx.translateBy(x: -size.width / 2, y: -size.height / 2)
        textNode.1.draw(size.bounds.focus(textNode.0.size).offsetBy(dx: 0, dy: -10), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
        ctx.restoreGState()
    })!
}
