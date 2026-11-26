import Cocoa
import TGUIKit
import TelegramCore
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import AlertsUI
import LocalAnimations
import DateUtils
import TelegramIconsTheme
import SwiftSignalKit
import Postbox

public final class SuspiciousAuthRowItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let session: NewSessionReview
    fileprivate let accept:(NewSessionReview)->Void
    fileprivate let revoke:(NewSessionReview)->Void
    
    fileprivate let title: TextViewLayout
    fileprivate let info: TextViewLayout

    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, session: NewSessionReview, accept:@escaping(NewSessionReview)->Void, revoke:@escaping(NewSessionReview)->Void) {
        self.context = context
        self.session = session
        self.revoke = revoke
        self.accept = accept
        
        self.title = .init(.initialize(string: strings().newSessionReviewItemTitle, color: theme.colors.text, font: .medium(.title)), alignment: .center)
        
        self.info = .init(.initialize(string: strings().newSessionReviewItemText(session.device, session.location), color: theme.colors.grayText, font: .normal(.text)), alignment: .center)

        
        super.init(initialSize, stableId: stableId)
    }
    
    public override var height: CGFloat {
        var height: CGFloat = 0

        height += 5
        height += 10
        height += title.layoutSize.height
        height += 4
        height += info.layoutSize.height
        height += 10
        height += 20
        height += 10
        height += 5

        return height
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)

        // 20 = container insets (10 each side) + 20 = container internal padding
        self.title.measure(width: width - 40)
        self.info.measure(width: width - 40)

        return true
    }
    
    public func _revoke() {
        self.revoke(self.session)
    }
    public func _accept() {
        self.accept(self.session)
    }
    
    public override func viewClass() -> AnyClass {
        return SuspiciousAuthRowView.self
    }

    public override var accessibilityLabel: String? {
        return title.attributedString.string
    }

    public override var accessibilityValue: String? {
        return info.attributedString.string
    }
}


private final class SuspiciousAuthRowView : GeneralRowView {
    private let container = View()
    private let titleView = TextView()
    private let infoView = TextView()
    private let accept = TextButton()
    private let revoke = TextButton()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        container.layer?.cornerRadius = 10
        if #available(macOS 10.15, *) {
            container.layer?.cornerCurve = .continuous
        }
        container.layer?.borderWidth = 1

        addSubview(container)
        container.addSubview(titleView)
        container.addSubview(infoView)
        container.addSubview(accept)
        container.addSubview(revoke)

        titleView.userInteractionEnabled = false
        titleView.isSelectable = false

        infoView.userInteractionEnabled = false
        infoView.isSelectable = false


        accept.scaleOnClick = true
        accept.autoSizeToFit = false

        revoke.scaleOnClick = true
        revoke.autoSizeToFit = false

        accept.set(handler: { [weak self] _ in
            if let item = self?.item as? SuspiciousAuthRowItem {
                item._accept()
            }
        }, for: .Click)

        revoke.set(handler: { [weak self] _ in
            if let item = self?.item as? SuspiciousAuthRowItem {
                item._revoke()
            }
        }, for: .Click)

    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)

        guard let item = item as? SuspiciousAuthRowItem else {
            return
        }

        container.backgroundColor = theme.colors.background.withAlphaComponent(0.4)
        container.layer?.borderColor = theme.colors.border.cgColor

        titleView.update(item.title)
        infoView.update(item.info)

        accept.set(font: .medium(.text), for: .Normal)
        accept.set(text: strings().newSessionItsMe, for: .Normal)
        accept.set(color: theme.colors.accent, for: .Normal)
        accept.sizeToFit()

        revoke.set(font: .medium(.text), for: .Normal)
        revoke.set(text: strings().newSessionIsntMe, for: .Normal)
        revoke.set(color: theme.colors.redUI, for: .Normal)
        revoke.sizeToFit()

        needsLayout = true
    }

    public override func layout() {
        super.layout()

        let inset: CGFloat = 5
        let padding: CGFloat = 5
        container.frame = NSMakeRect(inset, padding, frame.width - inset * 2, frame.height - padding * 2)

        titleView.centerX(y: 10)
        infoView.centerX(y: titleView.frame.maxY + 4)

        accept.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, (container.frame.width / 2 - accept.frame.width) / 2), infoView.frame.maxY + 10))

        revoke.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, container.frame.width / 2 + (container.frame.width / 2 - revoke.frame.width) / 2), infoView.frame.maxY + 10))

    }
}
