import Cocoa
import TGUIKit
import GeneralRows
import TelegramTheme
import Localization

private let walletKeyUpdateCircleSize: CGFloat = 90
private let walletKeyUpdateIconSize: CGFloat = 52

private func walletTransactionKeyUpdateImage() -> CGImage? {
    var icon: CGImage? = nil
    if let url = Bundle.module.url(forResource: "WalletTransactionKeyLarge", withExtension: "pdf"), let image = NSImage(contentsOf: url) {
        icon = image.precomposed(.white)
    }
    return generateImage(NSMakeSize(walletKeyUpdateCircleSize, walletKeyUpdateCircleSize), contextGenerator: { size, ctx in
        ctx.clear(NSMakeRect(0, 0, size.width, size.height))
        ctx.saveGState()
        ctx.addEllipse(in: NSMakeRect(0, 0, size.width, size.height))
        ctx.clip()
        let colors = [NSColor(rgb: 0x9aa0ac).cgColor, NSColor(rgb: 0xb8bdc7).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(gradient, start: NSMakePoint(0, size.height), end: NSMakePoint(0, 0), options: [])
        }
        ctx.restoreGState()
        if let icon {
            let rect = NSMakeRect((size.width - walletKeyUpdateIconSize) / 2, (size.height - walletKeyUpdateIconSize) / 2, walletKeyUpdateIconSize, walletKeyUpdateIconSize)
            ctx.interpolationQuality = .high
            ctx.draw(icon, in: rect)
        }
    })
}

final class WalletTransactionKeyUpdateRowItem: GeneralRowItem {
    fileprivate let titleLayout: TextViewLayout
    fileprivate let image: CGImage?

    init(_ initialSize: NSSize, stableId: AnyHashable) {
        self.titleLayout = TextViewLayout(.initialize(string: strings().walletTransactionKeyUpdateRowItemTitle, color: theme.colors.text, font: .medium(22)), maximumNumberOfLines: 1)
        self.image = walletTransactionKeyUpdateImage()
        super.init(initialSize, height: 168, stableId: stableId)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        titleLayout.measure(width: width - 100)
        return true
    }

    override func viewClass() -> AnyClass {
        return WalletTransactionKeyUpdateRowView.self
    }

    override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class WalletTransactionKeyUpdateRowView: GeneralRowView {
    private let imageView = ImageView()
    private let titleView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        imageView.isAccessibilityDecorative = true
        addSubview(imageView)
        addSubview(titleView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletTransactionKeyUpdateRowItem else {
            return
        }
        imageView.image = item.image
        imageView.setFrameSize(NSMakeSize(walletKeyUpdateCircleSize, walletKeyUpdateCircleSize))
        titleView.update(item.titleLayout)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        imageView.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, (frame.width - imageView.frame.width) / 2), 31))
        titleView.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, (frame.width - titleView.frame.width) / 2), 136))
    }
}
