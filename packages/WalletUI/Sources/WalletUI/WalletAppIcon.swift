import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramContext

func walletFallbackAppIcon(_ applicationName: String, size: CGFloat = 88, cornerRadius: CGFloat? = nil) -> CGImage? {
    let letter = applicationName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1).uppercased()
    return generateImage(NSMakeSize(size, size), contextGenerator: { size, ctx in
        ctx.clear(NSMakeRect(0, 0, size.width, size.height))
        ctx.setFillColor(NSColor(rgb: 0x2aabee).cgColor)
        if let cornerRadius {
            ctx.addPath(CGPath(roundedRect: NSMakeRect(0, 0, size.width, size.height), cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
            ctx.fillPath()
        } else {
            ctx.fillEllipse(in: NSMakeRect(0, 0, size.width, size.height))
        }
        guard !letter.isEmpty else {
            return
        }
        let attributedString = NSAttributedString(string: letter, attributes: [.font: NSFont.bold(min(40, size.height * 0.5)), .foregroundColor: NSColor.white])
        let line = CTLineCreateWithAttributedString(attributedString)
        let lineBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let lineOrigin = CGPoint(
            x: round(-lineBounds.origin.x + (size.width - lineBounds.size.width) / 2.0),
            y: round(-lineBounds.origin.y + (size.height - lineBounds.size.height) / 2.0)
        )
        ctx.translateBy(x: lineOrigin.x, y: lineOrigin.y)
        CTLineDraw(line, ctx)
        ctx.translateBy(x: -lineOrigin.x, y: -lineOrigin.y)
    })
}

func walletAppIconImage(data: Data?, applicationName: String, size: CGFloat, cornerRadius: CGFloat?) -> CGImage? {
    guard let data, let image = NSImage(data: data)?.precomposed() else {
        return walletFallbackAppIcon(applicationName, size: size, cornerRadius: cornerRadius)
    }
    return generateImage(NSMakeSize(size, size), contextGenerator: { size, ctx in
        let rect = NSMakeRect(0, 0, size.width, size.height)
        ctx.clear(rect)
        if let cornerRadius {
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        } else {
            ctx.addEllipse(in: rect)
        }
        ctx.clip()
        let imageSize = NSMakeSize(CGFloat(image.width), CGFloat(image.height))
        let scale = max(rect.width / max(1, imageSize.width), rect.height / max(1, imageSize.height))
        let drawSize = NSMakeSize(imageSize.width * scale, imageSize.height * scale)
        ctx.draw(image, in: rect.focus(drawSize))
    })
}

func walletFetchAppIcon(context: any AccountContextProtocol, icon: WalletTonConnectIcon?) -> Signal<Data?, NoError> {
    guard let icon, icon.size > 0, icon.size <= 2 * 1024 * 1024, icon.mimeType.lowercased().hasPrefix("image/") else {
        return .single(nil)
    }
    let mediaBox = context.account.postbox.mediaBox
    let resource = WebFileReferenceMediaResource(url: icon.url, size: Int64(icon.size), accessHash: icon.accessHash)
    let data = mediaBox.resourceData(resource)
    |> filter { $0.complete }
    |> take(1)
    |> map { data -> Data? in
        guard let value = try? Data(contentsOf: URL(fileURLWithPath: data.path)), value.count <= 2 * 1024 * 1024, NSImage(data: value) != nil else {
            return nil
        }
        return value
    }
    return Signal { subscriber in
        let fetch = fetchedMediaResource(mediaBox: mediaBox, userLocation: .other, userContentType: .image, reference: .standalone(resource: resource), statsCategory: .image).start()
        let load = data.start(next: { subscriber.putNext($0) }, completed: { subscriber.putCompletion() })
        return ActionDisposable {
            fetch.dispose()
            load.dispose()
        }
    }
}
