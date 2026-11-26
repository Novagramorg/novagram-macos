import Cocoa
import TGUIKit

func paidBadgeStarImage() -> NSImage {
    let root = (0..<6).reduce(URL(fileURLWithPath: #filePath)) { path, _ in path.deletingLastPathComponent() }
    let directory = root.appendingPathComponent("Telegram-Mac/Assets.xcassets/star_small.imageset")
    let image = NSImage(size: NSSize(width: 12, height: 12))
    for name in ["star_12.png", "star_12@2x.png"] {
        let representation = NSBitmapImageRep(data: try! Data(contentsOf: directory.appendingPathComponent(name)))!
        representation.size = image.size
        image.addRepresentation(representation)
    }
    return image
}

struct BadgeAmount { var value: Int64 }
struct SelectPeerPresentation { var premiumRequired: Set<Int> = [] }
struct BadgeIcons {
    var premium_required_forward = TelegramThemeHooks.shared.source.precomposed(.purple)
}

class PaidBadgeEnvironment: View {
    var photoBadge: ImageView?
    var paidMessageBadgeCache: SendPaidMessageBadgeCache?
    let image = ImageView(frame: NSRect(x: 0, y: 0, width: 36, height: 36))

    override convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 400, height: 60))
    }
    required init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(image)
    }
    required init?(coder: NSCoder) { fatalError() }
    func bind(item: ShortPeerRowItem, value: SelectPeerPresentation?, animated: Bool) {}
}
