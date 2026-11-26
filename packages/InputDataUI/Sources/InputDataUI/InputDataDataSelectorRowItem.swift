import ColorPalette
import GeneralRows
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import Cocoa
import TGUIKit

public class InputDataDataSelectorRowItem: GeneralRowItem, InputDataRowDataValue {

    private let updated:()->Void
    fileprivate var _value: InputDataValue {
        didSet {
            if _value != oldValue {
                updated()
            }
        }
    }
    fileprivate let placeholderLayout: TextViewLayout

    public var value: InputDataValue {
        return _value
    }
    
    fileprivate let values: [ValuesSelectorValue<InputDataValue>]
    public init(_ initialSize: NSSize, stableId: AnyHashable, value: InputDataValue, error: InputDataValueError?, placeholder: String, viewType: GeneralViewType, updated: @escaping()->Void, values: [ValuesSelectorValue<InputDataValue>]) {
        self._value = value
        self.updated = updated
        self.placeholderLayout = TextViewLayout(.initialize(string: placeholder, color: theme.colors.text, font: .normal(.text)), maximumNumberOfLines: 1)
        self.values = values
        super.init(initialSize, height: 42, stableId: stableId, viewType: viewType, error: error)
        _ = makeSize(initialSize.width, oldWidth: oldWidth)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        placeholderLayout.measure(width: 100)
        return success
    }
    
    public override func viewClass() -> AnyClass {
        return InputDataDataSelectorRowView.self
    }

    public override var accessibilityLabel: String? {
        return placeholderLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return values.first(where: { $0.value == value })?.localized
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func accessibilityPerformPress() -> Bool {
        guard let view = view as? InputDataDataSelectorRowView else {
            return false
        }
        view.overlay.send(event: .Click)
        return true
    }
    
}


final class InputDataDataSelectorRowView : GeneralContainableRowView {
    private let placeholderTextView = TextView()
    private let dataTextView = TextView()
    fileprivate let overlay = OverlayControl()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(placeholderTextView)
        addSubview(dataTextView)
        addSubview(overlay)
        placeholderTextView.userInteractionEnabled = false
        placeholderTextView.isSelectable = false
        dataTextView.userInteractionEnabled = false
        dataTextView.isSelectable = false
        
        overlay.set(handler: { [weak self] _ in
            guard let item = self?.item as? InputDataDataSelectorRowItem else {return}
            showModal(with: ValuesSelectorModalController(values: item.values, selected: item.values.first(where: {$0.value == item.value}), title: item.placeholderLayout.attributedString.string, onComplete: { [weak item] newValue in
                item?._value = newValue.value
                item?.noteHeightOfRow()
            }), for: InputDataUIHooks.shared.mainWindow())
        }, for: .Click)
    }
    
    override func shakeView() {
        dataTextView.shake()
    }
    
    
    override func layout() {
        super.layout()
        guard let item = item as? InputDataDataSelectorRowItem else {return}
        placeholderTextView.setFrameOrigin(item.viewType.innerInset.left, 14)
        
        dataTextView.textLayout?.measure(width: frame.width - item.viewType.innerInset.left - item.viewType.innerInset.right - 104)
        dataTextView.update(dataTextView.textLayout)
        dataTextView.setFrameOrigin(item.viewType.innerInset.left + 104, 14)
        
        overlay.frame = containerView.bounds
    }
    
    override func updateColors() {
        super.updateColors()
        placeholderTextView.backgroundColor = theme.colors.background
    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? InputDataDataSelectorRowItem else {return}
        placeholderTextView.update(item.placeholderLayout)
        
        var selected: ValuesSelectorValue<InputDataValue>?
        let index:Int? = item.values.firstIndex(where: { entry -> Bool in
            return entry.value == item.value
        })
        if let index = index {
            selected = item.values[index]
        }
        let layout = TextViewLayout(.initialize(string: selected?.localized ?? item.placeholderLayout.attributedString.string, color: selected == nil ? theme.colors.grayText : theme.colors.text, font: .normal(.text)), maximumNumberOfLines: 1)
        dataTextView.update(layout)
        
        needsLayout = true
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
