#if canImport(AppKit)
import AppKit
import RichTextEditorCore

@available(macOS 12, *)
public extension RGBAColor {
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

@available(macOS 12, *)
public extension NSColor {
    var rgba: RGBAColor {
        // getRed traps on catalog/dynamic colors — normalize to sRGB first.
        guard let c = usingColorSpace(.sRGB) else { return RGBAColor(red: 0, green: 0, blue: 0, alpha: 1) }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBAColor(red: r, green: g, blue: b, alpha: a)
    }
}

@available(macOS 12, *)
public enum FontResolver {
    public static func font(family: String?, size: CGFloat, bold: Bool, italic: Bool, serif: Bool = false, weight: NSFont.Weight = .regular) -> NSFont {
        var descriptor: NSFontDescriptor
        if let family, let custom = NSFont(name: family, size: size) {
            descriptor = custom.fontDescriptor
        } else if serif, let serifDesc = NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif) {
            descriptor = serifDesc
        } else {
            descriptor = NSFont.systemFont(ofSize: size).fontDescriptor
        }
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        if !traits.isEmpty {
            // NSFontDescriptor.withSymbolicTraits returns NON-optional (UIKit's was optional).
            descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(traits))
        }
        if weight != .regular {
            descriptor = descriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: weight]])
        }
        // NSFont(descriptor:size:) returns OPTIONAL (UIKit's was non-optional) — coalesce.
        return NSFont(descriptor: descriptor, size: size) ?? NSFont.systemFont(ofSize: size)
    }
}
#endif
