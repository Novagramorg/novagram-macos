import Cocoa
import LocalAnimations
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import GeneralRows
import InputDataUI

import TGUIKit

final class ChatListFolderIconsView : View {

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func initialize(environment: SidebarUIEnvironment, callback: @escaping(FolderIcon)->Void) {
        removeAllSubviews()

        for icon in allSidebarFolderIcons {
            let control = ImageButton(frame: NSMakeRect(0, 0, 40, 40))
            control.set(image: icon.icon(for: .settings, image: environment.folderImage), for: .Normal)
            control.setAccessibilityLabel(icon.emoticon.emoji ?? strings().voiceOverCommonEmoji)
            addSubview(control)
            control.set(handler: { _ in
                callback(icon)
            }, for: .Click)
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()

        var x: CGFloat = 10
        var y: CGFloat = 10
        for (i, subview) in subviews.enumerated() {
            subview.setFrameOrigin(NSMakePoint(x, y))
            x += subview.frame.width
            if (i + 1) % 5 == 0 {
                x = 10
                y += subview.frame.height
            }
        }
    }
}

class ChatListFilterFolderIconController: SidebarViewController<ChatListFolderIconsView> {
    private let select:(FolderIcon)->Void
    init(_ context: any AccountContextProtocol, environment: SidebarUIEnvironment, select: @escaping(FolderIcon)->Void) {
        self.select = select
        super.init(context, environment: environment)
        _frameRect = NSMakeRect(0, 0, 40 * 5 + 20, ceil(CGFloat(allSidebarFolderIcons.count) / 5) * 40 + 20)
        bar = .init(height: 0)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        genericView.initialize(environment: environment, callback: { [weak self] value in
            self?.select(value)
            self?.closePopover()
        })
        readyOnce()
    }
}
