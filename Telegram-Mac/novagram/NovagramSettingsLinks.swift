import Cocoa
import TGUIKit
import LocalAnimations
import NovagramCore

// tg://novagrampro, tg://novagram/<feature>, tg://fenixuz/<feature> and
// tg://settings/novagrampro[/<feature>] open Novagram Settings and, optionally, one sub-screen.
struct NovagramSettingsLink {
    let feature: String?

    private static let roots: Set<String> = ["novagrampro", "novagram", "fenixuz"]

    static func parse(_ url: String) -> NovagramSettingsLink? {
        var rest = url.lowercased()
        for prefix in ["tg://", "tg:"] where rest.hasPrefix(prefix) {
            rest = String(rest.dropFirst(prefix.count))
            break
        }
        guard url.lowercased() != rest else {
            return nil
        }
        rest = rest.components(separatedBy: "?").first ?? rest
        var parts = rest.components(separatedBy: "/").filter { !$0.isEmpty }
        if parts.first == "settings" {
            parts.removeFirst()
        }
        guard let root = parts.first, roots.contains(root) else {
            return nil
        }
        return NovagramSettingsLink(feature: parts.count > 1 ? parts[1] : nil)
    }
}

func openNovagramSettings(context: AccountContext, feature: String?) {
    let navigation = context.bindings.rootNavigation()
    navigation.push(NovagramSettingsController(context))
    guard let feature = feature else {
        return
    }
    switch feature {
    case "about":
        navigation.push(NovagramAboutController(context))
    case "bots":
        navigation.push(NovagramBotsController(context))
    case "tips":
        navigation.push(NovagramTipsController(context))
    case "text_style":
        navigation.push(NovagramTextStyleController(context))
    case "auto_text":
        navigation.push(NovagramAutoTextController(context))
    case "auto_translate":
        navigation.push(NovagramAutoTranslateController(context))
    case "translate_language", "translation_language", "language":
        navigation.push(NovagramTranslationLanguageController(context))
    default:
        break
    }
}

// Settings tab quick menu (right click on the gear): Novagram items under the upstream ones.
func novagramQuickMenuItems(context: AccountContext, selectSettingsTab: @escaping () -> Void) -> [ContextMenuItem] {
    let l10n = NovagramL10n.current
    var items: [ContextMenuItem] = [ContextSeparatorItem()]

    let ghostActive = NovagramGhostMode.isActive
    items.append(ContextMenuItem(ghostActive ? l10n.quickMenu_ghostDisable : l10n.quickMenu_ghostEnable, handler: {
        NovagramGhostMode.isActive = !ghostActive
    }, itemImage: ghostActive ? MenuAnimation.menu_eye.value : MenuAnimation.menu_eye_slash.value))

    let hiddenRevealed = NovagramHiddenChatsManager.shared.isRevealed
    items.append(ContextMenuItem(hiddenRevealed ? l10n.quickMenu_hiddenHide : l10n.quickMenu_hiddenShow, handler: {
        NovagramHiddenChatsManager.shared.toggleReveal(for: context.window)
    }, itemImage: hiddenRevealed ? MenuAnimation.menu_eye_locked.value : MenuAnimation.menu_eye.value))

    items.append(ContextMenuItem(l10n.quickMenu_novagramSettings, handler: {
        selectSettingsTab()
        openNovagramSettings(context: context, feature: nil)
    }, itemImage: MenuAnimation.menu_gear.value))

    return items
}
