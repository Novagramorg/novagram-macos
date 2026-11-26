import AppKit
import TGUIKit
import ColorPalette
import ThemeSettings
import InAppSettings
import TelegramTheme
import GeneralRows

enum UITestBootstrap {
    private static var retained: [NSImage] = []

    private static let installed: Void = {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
        System.liquidGlass = false
        for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
            let image = TestImages.named(name)
            _ = image.setName(name)
            retained.append(image)
        }
        GeneralRowsHooks.install(.placeholder)
        TelegramThemeHooks.install(TelegramThemeHooks(
            image: { TestImages.theme($0) },
            icons: { generateIcons(from: $0, bubbled: $1) },
            sendingFrame: { generateSendingFrame($0) },
            clockMinImage: { generateClockMinImage($0) },
            chatGroupToggleSelected: { generateChatGroupToggleSelected(foregroundColor: $0, backgroundColor: $1) },
            chatGroupToggleUnselected: { generateChatGroupToggleUnselected(foregroundColor: $0, backgroundColor: $1) },
            setDefaultTheme: { _ in },
            liteMode: { .standart },
            darkAppearance: { theme },
            liveStreamBadgeColor: { .systemRed }))
        let telegramTheme = generateTheme(palette: dayClassicPalette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false)
        telegramUpdateTheme(telegramTheme, window: nil, animated: false)
    }()

    static func install() {
        _ = installed
    }
}

enum TestImages {
    static let catalog = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Telegram-Mac/Assets.xcassets")

    static func key(_ value: String) -> String {
        return value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    static let index: [String: URL] = {
        var map: [String: URL] = [:]
        let enumerator = FileManager.default.enumerator(at: catalog, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "imageset" {
                map[key(url.deletingPathExtension().lastPathComponent)] = url
            }
        }
        return map
    }()

    static func load(_ directory: URL) -> NSImage? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("Contents.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["images"] as? [[String: Any]] else {
            return nil
        }
        let image = NSImage()
        for entry in entries {
            guard let file = entry["filename"] as? String, let rep = NSImageRep(contentsOf: directory.appendingPathComponent(file)) else {
                continue
            }
            let scale = CGFloat(Double((entry["scale"] as? String ?? "1x").dropLast()) ?? 1)
            if !(rep is NSPDFImageRep) {
                rep.size = NSSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale)
            }
            image.addRepresentation(rep)
            image.size = rep.size
        }
        return image.representations.isEmpty ? nil : image
    }

    static func named(_ name: String) -> NSImage {
        return index[key(name)].flatMap(load) ?? stub(name)
    }

    static func theme(_ value: TelegramThemeImage) -> NSImage {
        let name = key(String(describing: value))
        return (index[name] ?? index[name + "color"]).flatMap(load) ?? stub(name)
    }

    static func stub(_ name: String) -> NSImage {
        let hash = name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        let offset = CGFloat((hash & 0x7fffffff) % 12)
        return NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.black.setFill()
            NSRect(x: offset, y: 0, width: 4, height: rect.height).fill()
            return true
        }
    }
}
