import Cocoa
import TelegramCore
import Localization
import Postbox
import SwiftSignalKit
import TGUIKit
#if SHARE
import TelegramThemeShare
import TelegramContextShare
#else
import TelegramTheme
import TelegramContext
#endif

open class TelegramGenericViewController<T: NSView, Context: AccountContextProtocol>: GenericViewController<T> {

    public let context:Context
    private let languageDisposable:MetaDisposable = MetaDisposable()
    public init(_ context:Context) {
        self.context = context
        super.init()
    }


    open override func viewDidLoad() {
        super.viewDidLoad()
        languageDisposable.set(appearanceSignal.start(next: { [weak self] appearance in
            self?.updateLocalizationAndTheme(theme: appearance.presentation)
        }))
    }

    open override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)

        (self.genericView as? AppearanceViewProtocol)?.updateLocalizationAndTheme(theme: theme)
        requestUpdateBackBar()
        requestUpdateCenterBar()
        requestUpdateRightBar()
    }

    deinit {
        languageDisposable.dispose()
    }
}



open class TelegramViewController<Context: AccountContextProtocol>: TelegramGenericViewController<View, Context> {

}




open class TableViewController<Context: AccountContextProtocol>: TelegramGenericViewController<TableView, Context>, TableViewDelegate {



    open override func loadView() {
        super.loadView()
        if bar.height > 0 {
            genericView.contentInsets = NavigationBarView.contentTopInset
        }
        genericView.delegate = self
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        genericView.getBackgroundColor = {
           return theme.colors.listBackground
        }
    }

    open override func scrollup(force: Bool = false) {
        if isLoaded() {
            self.genericView.scroll(to: .up(!force))
        }
    }

    open override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
    }


    open func selectionDidChange(row:Int, item:TableRowItem, byClick:Bool, isNew:Bool) -> Void {

    }
    open func selectionWillChange(row:Int, item:TableRowItem, byClick: Bool) -> Bool {
        return false
    }
    open func isSelectable(row:Int, item:TableRowItem) -> Bool {
        return false
    }
    open func findGroupStableId(for stableId: AnyHashable) -> AnyHashable? {
        return nil
    }

    open override var enableBack: Bool {
        return true
    }

}


public enum ViewControllerState : Equatable {
    case Edit
    case Normal
    case Some
}


open class EditableViewController<T: NSView, Context: AccountContextProtocol>: TelegramGenericViewController<T, Context> {

    open var stackedBar: StackedBarView!
    public private(set) weak var editButton: TextButton?

    open var state: ViewControllerState = .Normal {
        didSet {
            if state != oldValue {
                updateEditStateTitles()
                requestUpdateRightBar()
                requestUpdateBackBar()
                requestUpdateCenterBar()
            }
        }
    }

    open override func getRightBarViewOnce() -> BarView {
        return stackedBar
    }

    open override var enableBack: Bool {
        return true
    }

    open func changeState() -> Void {
        let new: ViewControllerState
        if case .Normal = state {
            new = .Edit
        } else {
            new = .Normal
        }
        update(with: new)
    }

    open var doneString: String {
        return localizedString("Navigation.Done")
    }
    open var normalString: String {
        return localizedString("Navigation.Edit")
    }
    open var someString: String {
        return localizedString("Navigation.Some")
    }

    open func updateEditStateTitles() {
        let text: String
        switch state {
        case .Edit: text = doneString
        case .Normal: text = normalString
        case .Some: text = someString
        }
        editButton?.set(text: text, for: .Normal)
    }

    open override func requestUpdateRightBar() {
        super.requestUpdateRightBar()
        updateEditStateTitles()
    }

    open override func loadView() {
        stackedBar = StackedBarView(controller: self)
        let btn = stackedBar.addButton(text: normalString, handler: { [weak self] in
            self?.changeState()
        }) as? TextButton
        self.editButton = btn
        rightBarView = stackedBar
        updateEditStateTitles()
        super.loadView()
    }

    public override init(_ context: Context) {
        super.init(context)
    }

    open func update(with state: ViewControllerState) {
        self.state = state
        updateEditStateTitles()
    }

    open func set(editable: Bool) {
        editButton?.isHidden = !editable
        stackedBar?.isEnabled = editable
    }

    open func set(enabled: Bool) {
        stackedBar?.isEnabled = enabled
    }

    open override func updateNavigation(_ navigation: NavigationViewController?) {
        super.updateNavigation(navigation)
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

}
