import Cocoa
import TGUIKit
import TelegramTheme
import TelegramContext
import GeneralRows
import Localization

public final class WalletWordsGridRowItem: GeneralRowItem {

    fileprivate final class WordEntry {
        public let numberLayout: TextViewLayout
        public let wordLayout: TextViewLayout
        public var numberPoint: NSPoint = .zero
        public var wordPoint: NSPoint = .zero

        public init(index: Int, word: String) {
            self.numberLayout = TextViewLayout(.initialize(string: "\(index + 1).", color: theme.colors.grayText, font: NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .regular)), maximumNumberOfLines: 1)
            self.wordLayout = TextViewLayout(.initialize(string: word, color: theme.colors.text, font: .medium(17)))
        }
    }

    fileprivate let wordEntries: [WordEntry]
    private var contentHeight: CGFloat = 0

    public init(_ initialSize: NSSize, stableId: AnyHashable, words: [String], viewType: GeneralViewType = .legacy) {
        self.wordEntries = words.enumerated().map { index, word in
            WordEntry(index: index, word: word)
        }
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)

        let containerWidth = blockWidth - viewType.innerInset.left - viewType.innerInset.right
        let wordListWidth = min(containerWidth, 296)
        let minimumColumnWidth: CGFloat = 116
        let columnSpacing = min(40, max(16, wordListWidth - minimumColumnWidth * 2))
        let columnWidth = max(0, floorToScreenPixels((wordListWidth - columnSpacing) / 2))
        let wordListLayoutWidth = columnWidth * 2 + columnSpacing
        let wordListX = viewType.innerInset.left + floorToScreenPixels((containerWidth - wordListLayoutWidth) / 2)
        let numberWidth: CGFloat = 30
        let numberWordSpacing: CGFloat = 8
        let wordWidth = max(0, columnWidth - numberWidth - numberWordSpacing)
        let rowSpacing: CGFloat = 12
        let leftCount = min(12, (wordEntries.count + 1) / 2)
        let rightCount = max(0, wordEntries.count - leftCount)
        let rowCount = max(leftCount, rightCount)

        for entry in wordEntries {
            entry.numberLayout.measure(width: numberWidth)
            entry.wordLayout.measure(width: wordWidth)
        }

        var y: CGFloat = 0
        for rowIndex in 0 ..< rowCount {
            let wordIndices: [Int?] = [
                rowIndex < leftCount ? rowIndex : nil,
                rowIndex < rightCount ? rowIndex + leftCount : nil
            ]

            var rowHeight: CGFloat = 0
            for wordIndex in wordIndices {
                if let wordIndex {
                    let entry = wordEntries[wordIndex]
                    rowHeight = max(rowHeight, max(entry.numberLayout.layoutSize.height, entry.wordLayout.layoutSize.height))
                }
            }

            for columnIndex in 0 ..< wordIndices.count {
                guard let wordIndex = wordIndices[columnIndex] else {
                    continue
                }
                let entry = wordEntries[wordIndex]
                let columnX = wordListX + CGFloat(columnIndex) * (columnWidth + columnSpacing)
                entry.numberPoint = NSMakePoint(
                    columnX + numberWidth - entry.numberLayout.layoutSize.width,
                    y + floorToScreenPixels((rowHeight - entry.numberLayout.layoutSize.height) / 2)
                )
                entry.wordPoint = NSMakePoint(
                    columnX + numberWidth + numberWordSpacing,
                    y + floorToScreenPixels((rowHeight - entry.wordLayout.layoutSize.height) / 2)
                )
            }

            y += rowHeight
            if rowIndex != rowCount - 1 {
                y += rowSpacing
            }
        }
        self.contentHeight = y

        return true
    }

    public override var height: CGFloat {
        return contentHeight
    }

    public override func viewClass() -> AnyClass {
        return WalletWordsGridRowView.self
    }

    public override var accessibilityLabel: String? {
        return strings().walletWordsControllerPhraseTitle
    }
}

private final class WalletWordsGridRowView: GeneralContainableRowView {
    private var numberViews: [TextView] = []
    private var wordViews: [TextView] = []

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    public override var backdorColor: NSColor {
        guard let item = item as? GeneralRowItem else {
            return super.backdorColor
        }
        return item.viewType == .legacy ? theme.colors.background : super.backdorColor
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? WalletWordsGridRowItem else {
            return
        }

        while numberViews.count > item.wordEntries.count {
            numberViews.removeLast().removeFromSuperview()
            wordViews.removeLast().removeFromSuperview()
        }
        while numberViews.count < item.wordEntries.count {
            let numberView = TextView()
            numberView.userInteractionEnabled = false
            numberView.isSelectable = false
            addSubview(numberView)
            numberViews.append(numberView)

            let wordView = TextView()
            wordView.userInteractionEnabled = false
            wordView.isSelectable = false
            wordView.isAccessibilitySensitive = true
            addSubview(wordView)
            wordViews.append(wordView)
        }

        for (i, entry) in item.wordEntries.enumerated() {
            numberViews[i].update(entry.numberLayout)
            wordViews[i].update(entry.wordLayout)
        }

        needsLayout = true
    }

    public override func updateColors() {
        super.updateColors()
        for view in numberViews {
            view.backgroundColor = backdorColor
        }
        for view in wordViews {
            view.backgroundColor = backdorColor
        }
    }

    public override func layout() {
        super.layout()

        guard let item = item as? WalletWordsGridRowItem else {
            return
        }

        for (i, entry) in item.wordEntries.enumerated() {
            guard i < numberViews.count else {
                break
            }
            numberViews[i].setFrameOrigin(entry.numberPoint)
            wordViews[i].setFrameOrigin(entry.wordPoint)
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
