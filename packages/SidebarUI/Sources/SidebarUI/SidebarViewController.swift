import Cocoa
import TGUIKit
import TelegramContext
import TelegramTheme
import SwiftSignalKit

public class SidebarViewController<T: NSView>: GenericViewController<T> {
    let context: any AccountContextProtocol
    let environment: SidebarUIEnvironment
    private let appearanceDisposable = MetaDisposable()

    init(_ context: any AccountContextProtocol, environment: SidebarUIEnvironment) {
        self.context = context
        self.environment = environment
        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        appearanceDisposable.set(appearanceSignal.start(next: { [weak self] appearance in
            self?.updateLocalizationAndTheme(theme: appearance.presentation)
        }))
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        (genericView as? AppearanceViewProtocol)?.updateLocalizationAndTheme(theme: theme)
        requestUpdateBackBar()
        requestUpdateCenterBar()
        requestUpdateRightBar()
    }

    deinit {
        appearanceDisposable.dispose()
    }
}
