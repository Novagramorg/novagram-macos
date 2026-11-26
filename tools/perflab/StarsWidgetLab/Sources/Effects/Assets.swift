import AppKit
import TGUIKit

enum ThemeImage { case starReactionParticle }
struct TelegramThemeHooks {
    static let shared = TelegramThemeHooks()
    private static let particle: NSImage = {
        let image = NSImage(size: CGSize(width: 22, height: 22))
        for name in ["star", "star@2x"] {
            let data = try! Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "png")!)
            let representation = NSBitmapImageRep(data: data)!
            representation.size = image.size
            image.addRepresentation(representation)
        }
        return image
    }()
    func image(_ key: ThemeImage) -> NSImage { Self.particle }
}
let starsGradient = [NSColor(0xFFAC04), NSColor(0xFFCA35)]
