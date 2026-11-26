import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import TelegramMediaUtils
import TelegramMedia
import LocalAnimations
import CurrencyFormat
import PremiumStatusUI
import SceneEffects
import DustLayer
import InAppPurchaseManager
import ObjcUtils
import PremiumUI
import CalendarUtils
import DateUtils
import LokiRng
import FoundationUtils
import InputView
import InputTextView


public final class DurationOptionItem : GeneralRowItem {

    fileprivate let title: TextViewLayout
    fileprivate let desc: TextViewLayout
    fileprivate let total: TextViewLayout
    fileprivate let discount: TextViewLayout?
    fileprivate let selected: Bool
    fileprivate let option: PaymentOption
    fileprivate let toggleOption: (PaymentOption)->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, option: PaymentOption, selected: Bool, viewType: GeneralViewType, toggleOption: @escaping(PaymentOption)->Void) {
        self.selected = selected
        self.option = option
        self.toggleOption = toggleOption
        self.title = .init(.initialize(string: option.title, color: theme.colors.text, font: .medium(.text)))
        self.desc = .init(.initialize(string: option.desc, color: theme.colors.grayText, font: .normal(.short)))
        self.total = .init(.initialize(string: option.total, color: theme.colors.grayText, font: .normal(.text)))
        if let discount = option.discount {
            self.discount = .init(.initialize(string: discount, color: theme.colors.underSelectedColor, font: .normal(.small)))
        } else {
            self.discount = nil
        }
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)

        self.total.measure(width: .greatestFiniteMagnitude)

        self.title.measure(width: self.blockWidth - viewType.innerInset.left - viewType.innerInset.right - total.layoutSize.width - viewType.innerInset.right - viewType.innerInset.right)

        self.desc.measure(width: self.blockWidth - viewType.innerInset.left - viewType.innerInset.right - total.layoutSize.width - viewType.innerInset.right - viewType.innerInset.right)

        self.discount?.measure(width: .greatestFiniteMagnitude)

        return true
    }

    public override var height: CGFloat {
        return 42
    }

    public override var accessibilityLabel: String? {
        return title.attributedString.string
    }

    public override var accessibilityValue: String? {
        return [discount?.attributedString.string, desc.attributedString.string, total.attributedString.string].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .radioButton
    }

    public override var accessibilityToggleState: Bool? {
        return selected
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func accessibilityPerformPress() -> Bool {
        toggleOption(option)
        return true
    }

    public override func viewClass() -> AnyClass {
        return DurationOptionItemView.self
    }
}

private final class DurationOptionItemView : GeneralContainableRowView {


    private let titleView = TextView()
    private let descView = TextView()
    private let totalView = TextView()
    private var discountView: DiscountView?
    private var selectingControl = SelectingControl(unselectedImage: theme.icons.chatToggleUnselected, selectedImage: theme.icons.chatToggleSelected)
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(selectingControl)
        addSubview(titleView)
        addSubview(descView)
        addSubview(totalView)

        titleView.userInteractionEnabled = false
        titleView.isSelectable = false

        descView.userInteractionEnabled = false
        descView.isSelectable = false

        totalView.userInteractionEnabled = false
        totalView.isSelectable = false

        containerView.set(handler: { [weak self] _ in
            if let item = self?.item as? DurationOptionItem {
                item.toggleOption(item.option)
            }
        }, for: .Click)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? DurationOptionItem else {
            return
        }
        self.titleView.update(item.title)
        self.descView.update(item.desc)
        self.totalView.update(item.total)

        if let discount = item.discount {
            let current: DiscountView
            if let view = self.discountView {
                current = view
            } else {
                current = DiscountView(frame: .zero)
                self.discountView = current
                self.addSubview(current)
            }
            current.backgroundColor = theme.colors.accent
            current.layer?.cornerRadius = 3
            current.update(discount)
        } else if let view = self.discountView {
            performSubviewRemoval(view, animated: animated)
            self.discountView = nil
        }

        selectingControl.set(selected: item.selected, animated: animated)

        needsLayout = true

    }

    public override func layout() {
        super.layout()
        guard let item = item as? GeneralRowItem else {
            return
        }
        selectingControl.centerY(x: item.viewType.innerInset.left)
        totalView.centerY(x: containerView.frame.width - totalView.frame.width - item.viewType.innerInset.right)
        titleView.setFrameOrigin(NSMakePoint(selectingControl.frame.maxX + item.viewType.innerInset.left, 4))

        if let discount = discountView {
            discount.setFrameOrigin(NSMakePoint(selectingControl.frame.maxX + item.viewType.innerInset.left, containerView.frame.height - discount.frame.height - 4))
            descView.setFrameOrigin(NSMakePoint(discount.frame.maxX + 4, containerView.frame.height - descView.frame.height - 4))
        } else {
            descView.setFrameOrigin(NSMakePoint(selectingControl.frame.maxX + item.viewType.innerInset.left, containerView.frame.height - descView.frame.height - 4))
        }
    }
}
