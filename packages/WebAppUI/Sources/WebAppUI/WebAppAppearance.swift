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

public func generateWebAppThemeParams(_ presentationTheme: PresentationTheme) -> [String: Any] {
    return [
        "bg_color": Int32(bitPattern: presentationTheme.colors.background.rgb),
        "text_color": Int32(bitPattern: presentationTheme.colors.text.rgb),
        "hint_color": Int32(bitPattern: presentationTheme.colors.grayText.rgb),
        "link_color": Int32(bitPattern: presentationTheme.colors.link.rgb),
        "button_color": Int32(bitPattern: presentationTheme.colors.accent.rgb),
        "button_text_color": Int32(bitPattern: presentationTheme.colors.underSelectedColor.rgb),
        "secondary_bg_color":Int32(bitPattern: presentationTheme.colors.listBackground.rgb),
        "header_bg_color": Int32(bitPattern: presentationTheme.colors.listBackground.rgb),
        "accent_text_color": Int32(bitPattern: presentationTheme.colors.accent.rgb),
        "section_bg_color": Int32(bitPattern: presentationTheme.colors.background.rgb),
        "section_header_text_color": Int32(bitPattern: presentationTheme.colors.listGrayText.rgb),
        "subtitle_text_color": Int32(bitPattern: presentationTheme.colors.grayText.rgb),
        "destructive_text_color": Int32(bitPattern: presentationTheme.colors.redUI.rgb),
        "bottom_bar_bg_color": Int32(bitPattern: presentationTheme.colors.grayForeground.rgb),
        "section_separator_color": Int32(bitPattern: presentationTheme.colors.border.rgb)
    ]
}

public func generateContextMenuInstantView(color: NSColor, size: NSSize = NSMakeSize(20, 20)) -> NSImage {
    let icon = TelegramThemeHooks.shared.image(.iconInstantViewFavicon).precomposed(theme.colors.darkGrayText, flipVertical: true)
    return generateImage(size, rotatedContext: { size, ctx in
        ctx.clear(size.bounds)
        ctx.round(size, 4)
        ctx.setFillColor(color.cgColor)
        ctx.fill(size.bounds)
        
        ctx.draw(icon, in: size.bounds.focus(icon.backingSize))
    }).flatMap {
        NSImage(cgImage: $0, size: size)
    }!
}

public func generateContextMenuUrl(color: NSColor, state: WebpageModalState?, size: NSSize = NSMakeSize(20, 20)) -> NSImage {
    
    let text: String
    if state?.error != nil {
        text = "!"
    } else if let url = state?.url, let parsedUrl = URL(string: url) {
        text = parsedUrl.host?.first.flatMap(String.init) ?? "!"
    } else {
        text = "!"
    }
    
    let textNode = TextNode.layoutText(.initialize(string: text.uppercased(), color: theme.colors.darkGrayText, font: .medium(.text)), nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, 20), nil, false, .center)
    
    return generateImage(size, rotatedContext: { size, ctx in
        ctx.clear(size.bounds)
        ctx.round(size, 4)
        ctx.setFillColor(color.cgColor)
        ctx.fill(size.bounds)
        
        textNode.1.draw(size.bounds.focus(textNode.0.size), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
    }).flatMap {
        NSImage(cgImage: $0, size: size)
    }!
}

public func generateContextMenuSubsCount(_ count: Int32?) -> CGImage? {
    
    guard let count else {
        return nil
    }
    
    let presentation = AppMenu.Presentation.current(theme.colors)
    let membersImage = TelegramThemeHooks.shared.image(.iconMiniAppMembers).precomposed(presentation.disabledTextColor, flipVertical: true)

    let textNode = TextNode.layoutText(.initialize(string: Int64(count).prettyNumber, color: presentation.disabledTextColor, font: .normal(.text)), nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, 20), nil, false, .center)
    var size = textNode.0.size
    size.width += membersImage.backingSize.width
    return generateImage(size, rotatedContext: { size, ctx in
        ctx.clear(size.bounds)
        ctx.draw(membersImage, in: size.bounds.focusY(membersImage.backingSize, x: 0))
        textNode.1.draw(size.bounds.focusY(textNode.0.size, x: membersImage.backingSize.width), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
    })
}
