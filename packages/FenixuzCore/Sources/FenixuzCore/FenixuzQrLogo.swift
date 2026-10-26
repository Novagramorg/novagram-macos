import AppKit

// The Novagram logo for the center of QR codes (login, invite links, QR Studio), like iOS:
// the app icon cut to a circle, with an optional transparent ring so the QR background
// separates the logo from the modules.
public enum FenixuzQrLogo {
    public static func cgImage(pixelSide: Int, ringFraction: CGFloat = 0.08) -> CGImage? {
        guard pixelSide > 0, let icon = NSApp?.applicationIconImage else {
            return nil
        }
        let side = CGFloat(pixelSide)
        guard let context = CGContext(data: nil, width: pixelSide, height: pixelSide, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        let ring = side * ringFraction
        let circle = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: ring, dy: ring)
        context.addEllipse(in: circle)
        context.clip()
        // macOS app icons keep a transparent margin around the rounded square (about 10% per side),
        // so the icon is drawn larger than the circle until its blue square fills it.
        let iconRect = circle.insetBy(dx: -circle.width * 0.125, dy: -circle.height * 0.125)
        var proposed = iconRect
        guard let iconImage = icon.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(iconImage, in: iconRect)
        return context.makeImage()
    }

    public static func image(side: CGFloat, ringFraction: CGFloat = 0.08) -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        guard let cgImage = cgImage(pixelSide: Int(ceil(side * scale)), ringFraction: ringFraction) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSMakeSize(side, side))
    }
}
