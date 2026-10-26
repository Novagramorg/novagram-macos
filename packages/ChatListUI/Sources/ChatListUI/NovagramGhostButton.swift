import Cocoa
import TGUIKit
import TelegramTheme
import NovagramCore

// Ghost mode quick toggle in the chat list header (Settings → Novagram → Chat → Ghost mode button).
func novagramUpdateGhostButton(_ current: ImageButton?, in container: NSView, allowed: Bool, animated: Bool) -> ImageButton? {
    guard allowed, NovagramGhostMode.isButtonVisible else {
        if let current {
            performSubviewRemoval(current, animated: animated)
        }
        return nil
    }
    let button: ImageButton
    if let current {
        button = current
    } else {
        button = ImageButton(frame: NSMakeRect(0, 0, 30, 30))
        button.layer?.cornerRadius = .cornerRadius
        button.autohighlight = false
        button.animates = false
        button.scaleOnClick = true
        container.addSubview(button)
        button.set(handler: { [weak container] control in
            NovagramGhostMode.toggle()
            if let container, let control = control as? ImageButton {
                _ = novagramUpdateGhostButton(control, in: container, allowed: true, animated: false)
            }
        }, for: .Click)
    }
    // The asset is an upright portrait ghost (~455x491): draw it small, without the vertical flip.
    let size = NSMakeSize(20, 22)
    let image = NSImage(named: NovagramGhostMode.isActive ? "NovagramGhostActive" : "NovagramGhostInactive")
    image?.size = size
    let icon = NovagramGhostMode.isActive ? image?.precomposed(flipVertical: false) : image?.precomposed(theme.colors.grayIcon, flipVertical: false)
    if let icon {
        button.set(image: icon, for: .Normal)
        button.set(image: icon, for: .Hover)
        button.set(image: icon, for: .Highlight)
    }
    button.toolTip = NovagramL10n.current.settings_chat_ghost_title
    return button
}
