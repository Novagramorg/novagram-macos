# Create InputDataController

Create a new UI controller using the InputDataController pattern for Telegram macOS.

## User Request
$ARGUMENTS

---

## Architecture Overview

The Telegram macOS project uses **InputDataController** for list/form-based UI. This is a reactive pattern that separates data, business logic, and UI.

**Data Flow:** `State (ValuePromise) → entries() function → InputDataEntry[] → TableView`

---

## Controller Structure Template

```swift
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox

// MARK: - Arguments
// Handles callbacks and context - passed to entries function
private final class Arguments {
    let context: AccountContext
    // Add action callbacks here
    let someAction: () -> Void
    let itemSelected: (ItemType) -> Void

    init(context: AccountContext,
         someAction: @escaping () -> Void,
         itemSelected: @escaping (ItemType) -> Void) {
        self.context = context
        self.someAction = someAction
        self.itemSelected = itemSelected
    }
}

// MARK: - State
// Immutable data model - must be Equatable
private struct State: Equatable {
    var items: [ItemType] = []
    var selectedId: String? = nil
    var isLoading: Bool = false
}

// MARK: - Entry Identifiers
// Stable identifiers for row items
private let _id_header = InputDataIdentifier("_id_header")
private let _id_description = InputDataIdentifier("_id_description")

// Dynamic identifier pattern for lists
private func _id_item(_ id: String) -> InputDataIdentifier {
    return InputDataIdentifier("_id_item_\(id)")
}

// MARK: - Entries
// Generates UI rows from state
private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    // Section break
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    // Add your entries here...

    // Final section break
    entries.append(.sectionId(sectionId, type: .normal))

    return entries
}

// MARK: - Controller
func MyController(context: AccountContext) -> InputDataController {
    let actionsDisposable = DisposableSet()

    // State management
    let initialState = State()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    // Arguments with action handlers
    let arguments = Arguments(
        context: context,
        someAction: {
            updateState { current in
                var current = current
                // Modify state
                return current
            }
        },
        itemSelected: { item in
            updateState { current in
                var current = current
                current.selectedId = item.id
                return current
            }
        }
    )

    // Reactive signal
    let signal = statePromise.get()
        |> deliverOnPrepareQueue
        |> map { state in
            return InputDataSignalValue(entries: entries(state, arguments: arguments))
        }

    // Create controller
    let controller = InputDataController(
        dataSignal: signal,
        title: "Controller Title",
        hasDone: false  // Set true for forms with save button
    )

    // Load initial data
    actionsDisposable.add(
        context.engine.someDataSource()
            .start(next: { data in
                updateState { current in
                    var current = current
                    current.items = data
                    return current
                }
            })
    )

    // Cleanup
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    return controller
}
```

---

## Entry Types Reference

### Section Break
```swift
entries.append(.sectionId(sectionId, type: .normal))
// OR with custom spacing:
entries.append(.sectionId(sectionId, type: .customModern(10)))
sectionId += 1
```

### Description/Header Text
```swift
entries.append(.desc(
    sectionId: sectionId,
    index: index,
    text: .plain("SECTION HEADER"),
    data: .init(
        color: theme.colors.listGrayText,
        viewType: .textTopItem  // or .textBottomItem
    )
))
index += 1
```

### General Interactive Item
```swift
entries.append(.general(
    sectionId: sectionId,
    index: index,
    value: .none,
    error: nil,
    identifier: _id_myItem,
    data: .init(
        name: "Item Title",
        color: theme.colors.text,
        icon: NSImage(named: "icon")?.precomposed(theme.colors.accent),
        type: .next,  // See interaction types below
        viewType: .singleItem,  // See view types below
        enabled: true,
        description: "Optional subtitle",
        action: {
            arguments.someAction()
        }
    )
))
index += 1
```

**Interaction Types:**
- `.none` - No interaction indicator
- `.next` - Chevron `>` indicator
- `.selectable(Bool)` - Radio button (checkmark when true)
- `.switchable(Bool)` - Toggle switch
- `.context(String)` - Right-side text label
- `.button(String)` - Button style
- `.badge(String, NSColor)` - Badge indicator
- `.loading` - Loading spinner
- `.image(CGImage)` - Image display

**View Types (positioning in section):**
- `.singleItem` - Only item in section (rounded corners all around)
- `.firstItem` - First item (rounded top corners)
- `.innerItem` - Middle item (no rounded corners)
- `.lastItem` - Last item (rounded bottom corners)
- `.legacy` - Old style

**Auto View Type for Lists:**
```swift
let items = [/* your items */]
for (i, item) in items.enumerated() {
    let viewType = bestGeneralViewType(items, for: i)
    entries.append(.general(
        // ...
        viewType: viewType,
        // ...
    ))
}
```

### Text Input
```swift
entries.append(.input(
    sectionId: sectionId,
    index: index,
    value: .string(currentValue),
    error: nil,
    identifier: _id_textInput,
    mode: .plain,  // or .secure for passwords
    data: .init(viewType: .singleItem),
    placeholder: nil,
    inputPlaceholder: "Enter text...",
    filter: { text in text },  // Transform input
    limit: 100  // Max characters
))
index += 1
```

### Selector (Dropdown)
```swift
let options = [
    ValuesSelectorValue<InputDataValue>(localized: "Option 1", value: .string("opt1")),
    ValuesSelectorValue<InputDataValue>(localized: "Option 2", value: .string("opt2"))
]

entries.append(.selector(
    sectionId: sectionId,
    index: index,
    value: .string(selectedValue),
    error: nil,
    identifier: _id_selector,
    placeholder: "Select option",
    viewType: .singleItem,
    values: options
))
index += 1
```

### Custom Row Item
```swift
entries.append(.custom(
    sectionId: sectionId,
    index: index,
    value: .none,
    identifier: _id_custom,
    equatable: .init(state.someEquatableValue),  // For change detection
    comparable: nil,
    item: { initialSize, stableId in
        return MyCustomRowItem(
            initialSize,
            stableId: stableId,
            context: arguments.context,
            viewType: .singleItem
        )
    }
))
index += 1
```

### Animated Sticker Header
```swift
entries.append(.custom(
    sectionId: sectionId,
    index: index,
    value: .none,
    identifier: _id_header,
    equatable: nil,
    comparable: nil,
    item: { initialSize, stableId in
        return AnimatedStickerHeaderItem(
            initialSize,
            stableId: stableId,
            context: arguments.context,
            sticker: LocalAnimatedSticker.keychain,  // or other sticker
            text: .initialize(string: "Header Text", color: theme.colors.listGrayText, font: .normal(.text)),
            stickerSize: NSMakeSize(80, 80)
        )
    }
))
index += 1
```

---

## Custom Row Item Template

```swift
// MARK: - Custom Row Item
private final class MyRowItem: GeneralRowItem {
    fileprivate let context: AccountContext
    fileprivate let data: MyDataType
    fileprivate let titleLayout: TextViewLayout
    fileprivate let subtitleLayout: TextViewLayout
    fileprivate let arguments: Arguments

    init(_ initialSize: NSSize, stableId: AnyHashable,
         context: AccountContext, data: MyDataType,
         viewType: GeneralViewType, arguments: Arguments) {
        self.context = context
        self.data = data
        self.arguments = arguments

        self.titleLayout = TextViewLayout(
            .initialize(string: data.title, color: theme.colors.text, font: .medium(.text)),
            maximumNumberOfLines: 1
        )
        self.subtitleLayout = TextViewLayout(
            .initialize(string: data.subtitle, color: theme.colors.grayText, font: .normal(.short)),
            maximumNumberOfLines: 1
        )

        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        let contentWidth = blockWidth - viewType.innerInset.left - viewType.innerInset.right - 50
        titleLayout.measure(width: contentWidth)
        subtitleLayout.measure(width: contentWidth)
        return true
    }

    override func viewClass() -> AnyClass {
        return MyRowView.self
    }

    override var height: CGFloat {
        return 50
    }

    // Optional: Context menu
    override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        return .single([
            ContextMenuItem("Delete", handler: { [weak self] in
                if let data = self?.data {
                    self?.arguments.delete(data)
                }
            }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value)
        ])
    }
}

// MARK: - Custom Row View
private final class MyRowView: GeneralContainableRowView {
    private let titleView = TextView()
    private let subtitleView = TextView()
    private var imageView: ImageView?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleView.isSelectable = false
        titleView.userInteractionEnabled = false
        subtitleView.isSelectable = false
        subtitleView.userInteractionEnabled = false

        addSubview(titleView)
        addSubview(subtitleView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? MyRowItem else { return }

        titleView.update(item.titleLayout)
        subtitleView.update(item.subtitleLayout)
    }

    override func layout() {
        super.layout()

        guard let item = item as? MyRowItem else { return }

        let leftInset = item.viewType.innerInset.left
        titleView.setFrameOrigin(NSMakePoint(leftInset, 8))
        subtitleView.setFrameOrigin(NSMakePoint(leftInset, titleView.frame.maxY + 2))
    }
}
```

---

## Common Patterns

### Loading State
```swift
private struct State: Equatable {
    var isLoading: Bool = true
    var data: [Item] = []
}

// In entries:
if state.isLoading {
    entries.append(.custom(
        // ... loading indicator
        item: { initialSize, stableId in
            return LoadingTableItem(initialSize, stableId: stableId)
        }
    ))
} else {
    // Show actual content
}
```

### Form Validation
```swift
let controller = InputDataController(
    dataSignal: signal,
    title: "Form",
    hasDone: true,
    validateData: { data in
        if let name = data[_id_name]?.stringValue, name.isEmpty {
            return .fail(.fields([_id_name: .shake]))
        }
        return .success(.navigationBack)
    }
)
```

### Modal Presentation
```swift
let controller = MyController(context: context)
showModal(with: controller, for: context.window)

// Or with navigation:
let modalController = InputDataModalController(controller)
showModal(with: modalController, for: context.window)
```

### Context Menu on Items
```swift
entries.append(.general(
    // ...
    data: .init(
        // ...
        menuItems: {
            return [
                ContextMenuItem("Edit", handler: { /* edit */ }),
                ContextMenuItem("Delete", handler: { /* delete */ },
                    itemMode: .destruct,
                    itemImage: MenuAnimation.menu_delete.value)
            ]
        }
    )
))
```

---

## Reference Files

- `packages/InputDataUI/Sources/InputDataUI/InputDataController.swift` - Main controller class
- `packages/InputDataUI/Sources/InputDataUI/InputDataControllerEntries.swift` - Entry type definitions
- `packages/GeneralRows/Sources/GeneralRows/GeneralRowItem.swift` - Base row item classes
- `docs/swift/TemplateController/TemplateController.swift` - Template example, with instructions in `docs/swift/TemplateController/README.md`
- `packages/PasskeysUI/Sources/PasskeysUI/PasskeysController.swift` - Custom row items example
- `packages/SettingsUI/Sources/SettingsUI/LiteModeController.swift` - Switches and toggles example
- `packages/SettingsUI/Sources/SettingsUI/NotificationSoundController.swift` - Selectable lists example

---

Now implement the controller based on the user's request above.
