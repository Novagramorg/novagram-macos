import Cocoa

public func remainingTableHeight(for item: TableRowItem) -> CGFloat {
    if let table = item.table {
        var tableHeight: CGFloat = 0
        table.enumerateItems { current -> Bool in
            if current.index < item.index {
                tableHeight += current.height
            }
            return true
        }
        let height = table.frame.height == 0 ? item.initialSize.height : table.frame.height
        return height - tableHeight
    }
    return item.initialSize.height
}
