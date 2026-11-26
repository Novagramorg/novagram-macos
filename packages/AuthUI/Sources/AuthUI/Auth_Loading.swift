import Foundation
import TGUIKit
import Localization
import TelegramTheme
import TelegramContext
import FilePanels
import PhoneNumberUtils
import LocalAnimations
import TelegramUtils


public final class Auth_LoadingView: View {
    private let progressView = ProgressIndicator(frame: NSMakeRect(0, 0, 40, 40))

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(progressView)
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        progressView.progressColor = theme.colors.text
    }
    
    public override func layout() {
        super.layout()
        progressView.center()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public final class Auth_Loading : GenericViewController<Auth_LoadingView> {
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
    }
}
