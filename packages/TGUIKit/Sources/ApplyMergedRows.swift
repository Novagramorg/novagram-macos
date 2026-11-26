import Cocoa

public func applyMergedRows<T: Comparable & Identifiable>(_ tableView: TableView, current: inout [T], items: [T], animated: Bool, makeItem: (T) -> TableRowItem) {
    tableView.beginTableUpdates()

    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: current, rightList: items)

    for rdx in deleteIndices.reversed() {
        tableView.remove(at: rdx, animation: animated ? .effectFade : .none)
        current.remove(at: rdx)
    }

    for (idx, item, _) in indicesAndItems {
        _ = tableView.insert(item: makeItem(item), at: idx, animation: animated ? .effectFade : .none)
        current.insert(item, at: idx)
    }
    for (idx, item, _) in updateIndices {
        let item =  item
        tableView.replace(item: makeItem(item), at: idx, animated: animated)
        current[idx] = item
    }

    tableView.endTableUpdates()
}
