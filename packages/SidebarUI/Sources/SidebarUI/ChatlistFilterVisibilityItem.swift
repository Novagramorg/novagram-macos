import Cocoa
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import GeneralRows
import InputDataUI

import TGUIKit


private func generateThumb(_ basic: CGImage, active: CGImage?) -> CGImage {
    return generateImage(basic.backingSize, contextGenerator: { size, ctx in
        let rect = NSMakeRect(0, 0, size.width, size.height)
        ctx.clear(rect)

        ctx.draw(basic, in: rect)

        if let active = active {
            ctx.draw(active, in: rect)
        }
    })!
}

public final class ChatListFilterVisibilityItem: GeneralRowItem {

    public enum Source {
        case folders
        case forum
    }

    fileprivate let topViewLayout: TextViewLayout
    fileprivate let leftViewLayout: TextViewLayout

    fileprivate let topThumb: CGImage
    fileprivate let leftThumb: CGImage

    fileprivate let sidebar: Bool
    fileprivate let toggle:(Bool)->Void
    public init(_ initialSize: NSSize, images: (SidebarImage) -> NSImage, stableId: AnyHashable, sidebar: Bool, viewType: GeneralViewType, source: Source = .folders, toggle:@escaping(Bool)->Void) {

        self.sidebar = sidebar
        self.toggle = toggle

        switch source {
        case .folders:
            topViewLayout = TextViewLayout.init(.initialize(string: strings().chatListFilterTabBarOnTheTop, color: sidebar ? theme.colors.grayText : theme.colors.accent, font: .normal(.text)))
            leftViewLayout = TextViewLayout.init(.initialize(string: strings().chatListFilterTabBarOnTheLeft, color: sidebar ? theme.colors.accent : theme.colors.grayText, font: .normal(.text)))

            topThumb = generateThumb(images(.tabsselectTopGray).precomposed(theme.colors.grayIcon.withAlphaComponent(0.8)), active: images(.tabsselectTopSystemcol).precomposed(theme.colors.accent))

            leftThumb = generateThumb(images(.tabsselectLeftGray).precomposed(theme.colors.grayIcon.withAlphaComponent(0.8)), active: images(.tabsselectLeftSystemcol).precomposed(theme.colors.accent))

        case .forum:
            topViewLayout = TextViewLayout.init(.initialize(string: strings().chatListMonoforumTabBarTabs, color: sidebar ? theme.colors.grayText : theme.colors.accent, font: .normal(.text)))
            leftViewLayout = TextViewLayout.init(.initialize(string: strings().chatListMonoforumTabBarList, color: sidebar ? theme.colors.accent : theme.colors.grayText, font: .normal(.text)))

            topThumb = images(.iconForumTabs).precomposed(theme.colors.grayIcon.withAlphaComponent(0.8))
            leftThumb = images(.iconForumList).precomposed(theme.colors.grayIcon.withAlphaComponent(0.8))

        }




        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    public override var height: CGFloat {
        if blockWidth < (150 * 2) + viewType.innerInset.right * 3 {



            return viewType.innerInset.top + viewType.innerInset.bottom + viewType.innerInset.top + (topThumb.backingSize.height) * 2 + 20 + leftViewLayout.layoutSize.height + topViewLayout.layoutSize.height
        }

        return viewType.innerInset.top + viewType.innerInset.bottom + max(leftViewLayout.layoutSize.height, topViewLayout.layoutSize.height) + 10 + (topThumb.backingSize.height)
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)

        topViewLayout.measure(width: 140)
        leftViewLayout.measure(width: 140)

        return true
    }


    public override func viewClass() -> AnyClass {
        return ChatlistFilterVisibilityView.self
    }

    public override var accessibilityLabel: String? {
        return sidebar ? leftViewLayout.attributedString.string : topViewLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return strings().voiceOverCommonSelected
    }
}

private final class VisibilityContainerView : Control {
    private let imageView: ImageView = ImageView()
    private let textView: TextView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        addSubview(textView)

        imageView.isEventLess = true
        textView.isEventLess = true
        imageView.isAccessibilityDecorative = true
        textView.isAccessibilityDecorative = true
        textView.userInteractionEnabled = false
        textView.isSelectable = false
    }

    func update( _ text: TextViewLayout, image: CGImage, selected: Bool) -> Void {
        imageView.image = image
        imageView.sizeToFit()
        textView.update(text)
        setAccessibilityLabel(text.attributedString.string)
        setAccessibilityValue(selected ? strings().voiceOverCommonSelected : strings().voiceOverCommonNotSelected)

        imageView.layer?.cornerRadius = 8
        imageView.layer?.borderWidth = selected ? 2 : 0
        imageView.layer?.borderColor = selected ? theme.colors.accent.cgColor : theme.colors.grayIcon.cgColor
    }

    public override func layout() {
        super.layout()
        imageView.centerX(y: 0)
        textView.centerX(y: imageView.frame.maxY + 10)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


private final class ChatlistFilterVisibilityView : GeneralContainableRowView {
    private let leftItem:VisibilityContainerView = VisibilityContainerView(frame: .zero)
    private let topItem:VisibilityContainerView = VisibilityContainerView(frame: .zero)


    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(leftItem)
        addSubview(topItem)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? ChatListFilterVisibilityItem else {
            return
        }

        leftItem.setFrameSize(NSMakeSize(150, item.topThumb.backingSize.height + 10 + item.leftViewLayout.layoutSize.height))
        topItem.setFrameSize(NSMakeSize(150, item.topThumb.backingSize.height + 10 + item.topViewLayout.layoutSize.height))

        leftItem.update(item.leftViewLayout, image: item.leftThumb, selected: item.sidebar)
        topItem.update(item.topViewLayout, image: item.topThumb, selected: !item.sidebar)

        leftItem.removeAllHandlers()
        topItem.removeAllHandlers()


        topItem.set(handler: { [weak item] _ in
            item?.toggle(false)
        }, for: .Click)

        leftItem.set(handler: { [weak item] _ in
            item?.toggle(true)
        }, for: .Click)

        needsLayout = true
    }

    public override func layout() {
        super.layout()

        guard let item = item as? ChatListFilterVisibilityItem else {
            return
        }

        if containerView.frame.width < (leftItem.frame.width + topItem.frame.width) + item.viewType.innerInset.right * 3 {
            topItem.centerX(y: item.viewType.innerInset.top)
            leftItem.centerX(y: topItem.frame.maxY + item.viewType.innerInset.bottom)
        } else {
            let inset = (containerView.frame.width - (leftItem.frame.width + topItem.frame.width)) / 3
            topItem.setFrameOrigin(NSMakePoint(inset, item.viewType.innerInset.top))
            leftItem.setFrameOrigin(NSMakePoint(containerView.frame.width - leftItem.frame.width - inset, item.viewType.innerInset.top))
        }
    }


}
