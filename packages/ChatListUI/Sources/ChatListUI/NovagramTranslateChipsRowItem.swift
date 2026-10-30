import Cocoa
import TGUIKit
import TelegramTheme
import GeneralRows
import NovagramCore

final class NovagramTranslateChipsRowItem: GeneralRowItem {
    fileprivate static let chipHeight: CGFloat = 26
    fileprivate static let chipPadding: CGFloat = 10
    private static let spacing: CGFloat = 6
    private static let padding: CGFloat = 8

    let chips: NovagramTranslateChips
    fileprivate let titles: [String]
    fileprivate private(set) var frames: [NSRect] = []

    init(_ initialSize: NSSize, stableId: AnyHashable, chips: NovagramTranslateChips) {
        self.chips = chips
        self.titles = chips.targets.map(NovagramQueryTranslator.targetName)
        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }

    fileprivate func isOn(_ index: Int) -> Bool {
        return index < chips.targets.count && !chips.disabled.contains(chips.targets[index])
    }

    fileprivate func toggle(_ index: Int) {
        guard index < chips.targets.count else {
            return
        }
        chips.state.toggle(chips.targets[index])
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        let padding = NovagramTranslateChipsRowItem.padding
        let spacing = NovagramTranslateChipsRowItem.spacing
        let height = NovagramTranslateChipsRowItem.chipHeight
        let maxX = width - padding
        var x = padding
        var y = padding
        var frames: [NSRect] = []
        for title in titles {
            let textWidth = ceil(NSAttributedString(string: title, attributes: [.font: NSFont.normal(.text)]).size().width)
            let chipWidth = min(textWidth + NovagramTranslateChipsRowItem.chipPadding * 2, maxX - padding)
            if x > padding && x + chipWidth > maxX {
                x = padding
                y += height + spacing
            }
            frames.append(NSRect(x: x, y: y, width: chipWidth, height: height))
            x += chipWidth + spacing
        }
        self.frames = frames
        return true
    }

    override var height: CGFloat {
        return (frames.map { $0.maxY }.max() ?? 0) + NovagramTranslateChipsRowItem.padding
    }

    override func viewClass() -> AnyClass {
        return NovagramTranslateChipsRowView.self
    }
}

private final class NovagramTranslateChipsRowView: GeneralContainableRowView {
    private var buttons: [TextButton] = []

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? NovagramTranslateChipsRowItem else {
            return
        }
        while buttons.count < item.titles.count {
            let button = TextButton()
            button.scaleOnClick = true
            button.layer?.cornerRadius = NovagramTranslateChipsRowItem.chipHeight / 2
            button.set(handler: { [weak self] control in
                guard let self, let item = self.item as? NovagramTranslateChipsRowItem, let index = self.buttons.firstIndex(where: { $0 === control }) else {
                    return
                }
                item.toggle(index)
            }, for: .Click)
            containerView.addSubview(button)
            buttons.append(button)
        }
        while buttons.count > item.titles.count {
            buttons.removeLast().removeFromSuperview()
        }
        for (index, button) in buttons.enumerated() {
            let color = item.isOn(index) ? theme.colors.accent : theme.colors.grayText
            button.set(font: .normal(.text), for: .Normal)
            button.set(color: color, for: .Normal)
            button.set(background: color.withAlphaComponent(item.isOn(index) ? 0.12 : 0.08), for: .Normal)
            button.set(background: color.withAlphaComponent(0.2), for: .Highlight)
            button.set(text: item.titles[index], for: .Normal)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? NovagramTranslateChipsRowItem else {
            return
        }
        for (index, button) in buttons.enumerated() where index < item.frames.count {
            button.frame = item.frames[index]
        }
    }
}
