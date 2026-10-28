//
//  NovagramBrandColors.swift
//  Telegram-Mac
//
//  iOS portasi: submodules/Novagram/Brand/Sources/NovagramBrandColors.swift
//
//  Novagram brand palette — manba: https://novagram.uz/assets/css/style.css
//  Barcha Novagram moduli (auth splash, settings, IAP alert, Tasks, etc.) shu
//  yerdan rang oladi. Hech qachon hard-code qilingan hex'lar boshqa joyda.
//
//  iOS bilan farq: UIColor → NSColor. NSColor(rgb:) TGUIKit/Colors paketida
//  allaqachon mavjud (`packages/Colors/Sources/Colors/Colors.swift`), shuning
//  uchun bu file faqat konstantalar e'lon qiladi.
//

import Foundation
import AppKit
import TGUIKit

public enum NovagramBrandColors {
    // MARK: - Brand blues (same values as iOS)
    public static let brand50  = NSColor(rgb: 0xEAF6FF)
    public static let brand100 = NSColor(rgb: 0xCFE9FF)
    public static let brand300 = NSColor(rgb: 0x7CC3FD)
    public static let brand400 = NSColor(rgb: 0x36A8FA)
    public static let brand500 = NSColor(rgb: 0x0A9BF5)   // Primary brand (Novagram blue)
    public static let brand600 = NSColor(rgb: 0x0A85E8)   // Primary hover
    public static let brand700 = NSColor(rgb: 0x086FC6)   // Primary deep
    public static let brand900 = NSColor(rgb: 0x07406F)

    // Accent of the light themes when "Brand accent in light theme" is on.
    public static let lightThemeAccent = brand500

    // MARK: - Ink (dark text / dark backgrounds)
    public static let inkBase = NSColor(rgb: 0x0F1115)    // Dark bg (dark mode)
    public static let ink900  = NSColor(rgb: 0x0B1220)
    public static let ink800  = NSColor(rgb: 0x111827)
    public static let ink700  = NSColor(rgb: 0x1F2937)
    public static let ink600  = NSColor(rgb: 0x374151)
    public static let ink500  = NSColor(rgb: 0x6B7280)
    public static let ink400  = NSColor(rgb: 0x9CA3AF)
    public static let ink300  = NSColor(rgb: 0xD1D5DB)
    public static let ink200  = NSColor(rgb: 0xE5E7EB)
    public static let ink100  = NSColor(rgb: 0xF3F4F6)
    public static let ink50   = NSColor(rgb: 0xF9FAFB)

    // MARK: - Accents
    public static let accentAmber = NSColor(rgb: 0xF59E0B)
    public static let destructive = NSColor(rgb: 0xDC2626)
    public static let destructiveDark = NSColor(rgb: 0xB91C1C)

    // MARK: - Semantic aliases (use these in UI code; values may evolve)
    public static var primary:      NSColor { brand600 }   // CTA buttons
    public static var primaryLight: NSColor { brand500 }   // hover / pressed
    public static var primaryDeep:  NSColor { brand700 }
    public static var primaryAccent: NSColor { brand500 }  // text accent
}
