import Foundation
import TGUIKit
import TelegramTheme
import ColorPalette
import Localization

public final class SegmentTypesRowItem : GeneralRowItem {
    fileprivate let items: [ScrollableSegmentItem]
    fileprivate let callback:(Int64)->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, items: [ScrollableSegmentItem], viewType: GeneralViewType, callback:@escaping(Int64)->Void) {
        self.items = items
        self.callback = callback
        super.init(initialSize, height: 50, stableId: stableId, viewType: viewType)
    }
    
    public override func viewClass() -> AnyClass {
        return SegmentTypesRowView.self
    }

    public override var accessibilityLabel: String? {
        return items.first(where: { $0.selected })?.title ?? items.first?.title
    }
}

private final class SegmentTypesRowView: GeneralContainableRowView {
    private let segmentControl: ScrollableSegmentView
    public required init(frame frameRect: NSRect) {
        self.segmentControl = ScrollableSegmentView(frame: NSMakeRect(0, 0, frameRect.width, 50))
        super.init(frame: frameRect)
        addSubview(segmentControl)
        
        segmentControl.didChangeSelectedItem = { [weak self] selected in
            if let item = self?.item as? SegmentTypesRowItem {
                item.callback(selected.uniqueId)
            }
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? SegmentTypesRowItem else {
            return
        }
        segmentControl.updateItems(item.items, animated: animated)
        needsLayout = true
    }
    
    public override func layout() {
        segmentControl.frame = containerView.bounds
    }
}
