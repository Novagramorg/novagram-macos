import Cocoa
import TGUIKit
import Localization
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif


open class GeneralLoadingRowItem: GeneralRowItem {
    public let color: NSColor?
    public let bgColor: NSColor?
    public let _hasBorder: Bool?
    public let fillHeight: Bool
    public init(_ initialSize: NSSize, stableId: AnyHashable, viewType: GeneralViewType, color: NSColor? = nil, height: CGFloat = 42, backgroundColor: NSColor? = nil, hasBorder: Bool? = nil, fillHeight: Bool = false) {
        self.color = color
        self.bgColor = backgroundColor
        self._hasBorder = hasBorder
        self.fillHeight = fillHeight
        super.init(initialSize, height: height, stableId: stableId, viewType: viewType)
    }
    
    open override var height: CGFloat {
        if fillHeight, let table {
            return floor(table.frame.height / super.height) * super.height
        } else {
            return super.height
        }
    }
    
    open override var hasBorder: Bool {
        return _hasBorder ?? super.hasBorder
    }
    
    open override func viewClass() -> AnyClass {
        return GeneralLoadingRowView.self
    }

    open override var accessibilityLabel: String? {
        return strings().voiceOverCommonLoading
    }

    open override var accessibilityRole: NSAccessibility.Role? {
        return .busyIndicator
    }

    open override var accessibilityIncludesChildren: Bool {
        return false
    }
    
}

private final class GeneralLoadingRowView: GeneralContainableRowView {
    private let indicator: ProgressIndicator = ProgressIndicator(frame: NSMakeRect(0, 0, 20, 20))
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(indicator)
    }
    
    public override func layout() {
        super.layout()
        indicator.center()
    }
    
    public override var backdorColor: NSColor {
        if let item = item as? GeneralLoadingRowItem {
            if let color = item.bgColor {
                return color
            }
            if item.viewType == .legacy {
                return .clear
            }
        }
        return super.backdorColor
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func updateColors() {
        super.updateColors()
        guard let item = self.item as? GeneralLoadingRowItem else {
            return
        }
        indicator.progressColor = item.color ?? theme.colors.text
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
    }
}
