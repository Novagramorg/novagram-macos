import Cocoa
import TGUIKit
import Localization
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
import ColorPalette
#endif

open class LoadingTableItem: GeneralRowItem {

    public init(_ initialSize: NSSize, height: CGFloat, stableId: AnyHashable, viewType: GeneralViewType = .legacy, backgroundColor: NSColor = theme.colors.background) {
        super.init(initialSize, height: height, stableId: stableId, viewType: viewType, backgroundColor: backgroundColor)
    }
    
    open override func viewClass() -> AnyClass {
        return LoadingTableRowView.self
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


open class LoadingTableRowView : TableRowView {
    private let containerView = GeneralRowContainerView(frame: NSZeroRect)
    private let progress: ProgressIndicator = ProgressIndicator(frame: NSMakeRect(0, 0, 20, 20))
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        containerView.addSubview(progress)
        addSubview(containerView)
    }
    
    open override func viewDidMoveToWindow() {
        if let _ = window {
            progress.animates = true
        } else {
            progress.animates = false
        }
    }
    
    open override var backdorColor: NSColor {
        if let item = item as? GeneralRowItem {
            return item.backgroundColor
        }
        return theme.colors.background
    }
    
    open override func updateColors() {
        if let item = item as? GeneralRowItem {
            containerView.background = backdorColor
            backgroundColor = item.viewType.rowBackground
        }
    }
    
    open override func layout() {
        super.layout()
        
        if let item = item as? GeneralRowItem {
            switch item.viewType {
            case .legacy:
                containerView.frame = bounds
            case .modern:
                self.containerView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2), item.inset.top, item.blockWidth, frame.height - item.inset.bottom - item.inset.top)
            }
            self.containerView.setCorners(item.viewType.corners)
            progress.center()
        }
    }
    
    deinit {
        progress.animates = false
    }
    
    open override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        if let item = item as? GeneralRowItem {
            let contentRect: NSRect
            switch item.viewType {
            case .legacy:
                contentRect = bounds
            case .modern:
                contentRect = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2), item.inset.top, item.blockWidth, frame.height - item.inset.bottom - item.inset.top)
            }
            self.containerView.change(size: contentRect.size, animated: animated, corners: item.viewType.corners)
            self.containerView.change(pos: contentRect.origin, animated: animated)
        }
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
