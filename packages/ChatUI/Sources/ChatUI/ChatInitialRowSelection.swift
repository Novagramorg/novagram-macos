import Foundation

func chatInitialCenteredRows<Item>(count: Int, anchor: Int, viewportHeight: CGFloat, accountForAnchorHeight: Bool, makeItem: (Int) -> Item, height: (Item) -> CGFloat) -> (range: Range<Int>, items: [Item]) {
    precondition(anchor >= 0 && anchor < count)
    let anchorItem = makeItem(anchor)
    let anchorHeight = height(anchorItem)
    let viewportHeight = max(0, viewportHeight)
    let accountsForAnchor = accountForAnchorHeight && anchorHeight > 0 && anchorHeight < viewportHeight
    let sideHeight = accountsForAnchor ? max(0, (viewportHeight - anchorHeight) / 2) + 1 : viewportHeight / 2
    var lower = anchor
    var upper = anchor + 1
    var before: [Item] = []
    var after: [Item] = []
    var beforeHeight: CGFloat = 0
    var afterHeight: CGFloat = 0

    while (lower > 0 && (before.isEmpty || beforeHeight < sideHeight)) || (upper < count && (after.isEmpty || afterHeight < sideHeight)) {
        if upper < count && (after.isEmpty || afterHeight < sideHeight) {
            let item = makeItem(upper)
            after.append(item)
            afterHeight += height(item)
            upper += 1
        }
        if lower > 0 && (before.isEmpty || beforeHeight < sideHeight) {
            lower -= 1
            let item = makeItem(lower)
            before.append(item)
            beforeHeight += height(item)
        }
    }

    if accountsForAnchor {
        while anchorHeight + beforeHeight + afterHeight < viewportHeight + 1 && (lower > 0 || upper < count) {
            if upper < count {
                let item = makeItem(upper)
                after.append(item)
                afterHeight += height(item)
                upper += 1
            } else {
                lower -= 1
                let item = makeItem(lower)
                before.append(item)
                beforeHeight += height(item)
            }
        }
    }

    return (lower ..< upper, before.reversed() + [anchorItem] + after)
}
