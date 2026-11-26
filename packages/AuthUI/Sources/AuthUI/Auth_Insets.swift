import Foundation
import AppKit
import Localization
import TelegramTheme
import TelegramContext
import FilePanels
import PhoneNumberUtils
import LocalAnimations
import TelegramUtils


public struct Auth_Insets {
    public static let betweenNextView: CGFloat = 15 + 15 + 10
    public static let betweenError: CGFloat = 10
    public static let betweenHeader: CGFloat = 20
    public static let nextHeight: CGFloat = 36
    public static let logoSize: NSSize = NSMakeSize(140, 140)
    public static let wordSize: NSSize = NSMakeSize(100, 100)
    public static let qrSize: NSSize = NSMakeSize(210, 210)
    public static let qrAnimSize: NSSize = NSMakeSize(186, 186)
    public static let headerFont: NSFont = .medium(22)
    public static let infoFont: NSFont = .normal(13.5)
    public static let infoFontBold: NSFont = .medium(13.5)
}
