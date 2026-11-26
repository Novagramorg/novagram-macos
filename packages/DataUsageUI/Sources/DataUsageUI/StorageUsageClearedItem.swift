import Cocoa
import TGUIKit
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import FoundationUtils
import AlertsUI
import InAppSettings
import LocalAnimations
import SwiftSignalKit
import TelegramCore
import Postbox
import AvatarUI

public final class StorageUsageClearedItem: GeneralRowItem {
    public init(_ initialSize: NSSize, stableId: AnyHashable, viewType: GeneralViewType) {
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }
    
    public override func viewClass() -> AnyClass {
        return StorageUsageClearedView.self
    }
    
    public override var height: CGFloat {
        return 100
    }

    public override var accessibilityLabel: String? {
        return strings().storageUsageCleared
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class StorageUsageClearedView : TableRowView {
    private var circle: ImageView?
    private var check: ImageView?
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

    }
    
    public override func layout() {
        super.layout()
        circle?.center()
        check?.center()
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        
        let check = TelegramThemeHooks.shared.image(.iconStorageClearedCheck).precomposed(theme.colors.greenUI)
        let circle = generateImage(NSMakeSize(200, 200), contextGenerator: { size, ctx in
            ctx.clear(size.bounds)
            let startAngle = 2.0 * (CGFloat.pi) - CGFloat.pi / 2
            let endAngle = -(CGFloat.pi / 2)
            
            let radius = size.height / 2 - 10
            ctx.addArc(center: NSMakePoint(size.width * 0.5, size.width * 0.5), radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            
            ctx.setStrokeColor(theme.colors.greenUI.cgColor)
            ctx.setLineWidth(10);
            ctx.setLineCap(.round);
            ctx.strokePath()

        })!

        
        let current_circle: ImageView
        if let view = self.circle {
            current_circle = view
        } else {
            current_circle = ImageView()
            current_circle.isAccessibilityDecorative = true
            self.circle = current_circle
            addSubview(current_circle)
            current_circle.image = circle
            current_circle.setFrameSize(circle.backingSize.width * 0.5, circle.backingSize.height * 0.5)

            current_circle.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            current_circle.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.45)

        }
        current_circle.image = circle
        current_circle.setFrameSize(circle.backingSize.width * 0.5, circle.backingSize.height * 0.5)
        
        let current_check: ImageView
        if let view = self.check {
            current_check = view
        } else {
            current_check = ImageView()
            current_check.isAccessibilityDecorative = true
            self.check = current_check
            addSubview(current_check)
            current_check.image = check
            current_check.setFrameSize(check.backingSize.width * 0.5, check.backingSize.height * 0.5)

            current_check.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            current_check.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.45)

        }
        current_check.image = check
        current_check.setFrameSize(check.backingSize.width * 0.5, check.backingSize.height * 0.5)

        
        needsLayout = true
    }
}
