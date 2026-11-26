import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
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
import AvatarUI

public class StoragePieChartItem : GeneralRowItem {
    public let items: [PieChartView.Item]
    public let dynamicText: String
    public let context: any AccountContextProtocol
    public let peer: Peer?
    public let toggleSelected:(PieChartView.Item)->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, items: [PieChartView.Item], dynamicText: String, peer: Peer?, viewType: GeneralViewType, toggleSelected:@escaping(PieChartView.Item)->Void) {
        self.items = items
        self.context = context
        self.peer = peer
        self.dynamicText = dynamicText
        self.toggleSelected = toggleSelected
        super.init(initialSize, stableId: stableId, viewType: .singleItem)
    }
    
    public override var height: CGFloat {
        return 200
    }
    public override var accessibilityLabel: String? {
        if let peer = peer {
            return peer.displayTitle
        }
        return dynamicText
    }
    public override var accessibilityValue: String? {
        return peer != nil ? dynamicText : nil
    }
    public override func viewClass() -> AnyClass {
        return StoragePieChartItemView.self
    }
}
private class StoragePieChartItemView : GeneralRowView {
    private let pieChart = PieChartView(frame: NSMakeRect(0, 0, 200, 200), presentation: .init(strokeColor: theme.colors.background, strokeSize: 1, bgColor: theme.colors.background, totalTextColor: theme.colors.text, itemTextColor: .white))
    private var avatar: AvatarControl?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(pieChart)
    }
    
    public override func layout() {
        super.layout()
        pieChart.center()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? StoragePieChartItem else {
            return
        }
        
        self.pieChart.frame = self.focus(NSMakeSize(frame.width, item.height))
        self.pieChart.presentation = .init(strokeColor: theme.colors.listBackground, strokeSize: 1, bgColor: theme.colors.listBackground, totalTextColor: theme.colors.text, itemTextColor: .white)
        self.pieChart.update(items: item.items, dynamicText: item.dynamicText, animated: animated)
        
        self.pieChart.toggleSelected = item.toggleSelected
        
        if let peer = item.peer {
            let current: AvatarControl
            if let view = self.avatar {
                current = view
            } else {
                current = AvatarControl(font: .avatar(.title))
                current.setFrameSize(NSMakeSize(70, 70))
                addSubview(current, positioned: .below, relativeTo: pieChart)
                current.center()
                self.avatar = current
            }
            current.setPeer(account: item.context.account, peer: peer)
        } else if let view = self.avatar {
            performSubviewRemoval(view, animated: animated)
            self.avatar = nil
        }
        needsLayout = true
    }
}
