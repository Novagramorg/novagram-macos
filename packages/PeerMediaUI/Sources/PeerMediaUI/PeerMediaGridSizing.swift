import Foundation

struct PeerMediaGridSizing {
    let columns: Int
    private let cellWidth: CGFloat

    init(width: CGFloat, maximumColumns: Int) {
        let width = width.isFinite ? max(92, width) : 92
        var columns = max(1, maximumColumns)
        while columns > 1 && (width - CGFloat(columns * 2)) / CGFloat(columns) < 90 {
            columns -= 1
        }
        self.columns = columns
        self.cellWidth = (width - CGFloat(columns * 2)) / CGFloat(columns)
    }

    func itemCount(height: CGFloat) -> Int {
        guard height.isFinite, height > 0 else {
            return columns
        }
        let count = (height / cellWidth) * CGFloat(columns) + CGFloat(columns)
        guard count.isFinite, count < CGFloat(Int.max / 10) else {
            return columns
        }
        return Int(count)
    }
}
