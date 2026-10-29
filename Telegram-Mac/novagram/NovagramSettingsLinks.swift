import Cocoa
import TGUIKit
import LocalAnimations
import NovagramCore

// tg://novagrampro, tg://novagram/<feature>, tg://fenixuz/<feature> and
// tg://settings/novagrampro[/<feature>] open Novagram Settings and, optionally, one sub-screen.
// The `?f=<feature>` form (iOS alias) works too. Features use the iOS kebab-case slugs.
struct NovagramSettingsLink {
    let feature: String?

    private static let roots: Set<String> = ["novagrampro", "novagram", "fenixuz"]

    static func url(slug: String?) -> String {
        if let slug {
            return "tg://settings/novagrampro/\(slug)"
        }
        return "tg://settings/novagrampro"
    }

    static func parse(_ url: String) -> NovagramSettingsLink? {
        var rest = url.lowercased()
        for prefix in ["tg://", "tg:"] where rest.hasPrefix(prefix) {
            rest = String(rest.dropFirst(prefix.count))
            break
        }
        guard url.lowercased() != rest else {
            return nil
        }
        let pieces = rest.components(separatedBy: "?")
        rest = pieces.first ?? rest
        let queryFeature = pieces.count > 1 ? pieces[1].components(separatedBy: "&").first(where: { $0.hasPrefix("f=") }).map { String($0.dropFirst(2)) } : nil
        var parts = rest.components(separatedBy: "/").filter { !$0.isEmpty }
        if parts.first == "settings" {
            parts.removeFirst()
        }
        guard let root = parts.first, roots.contains(root) else {
            return nil
        }
        return NovagramSettingsLink(feature: parts.count > 1 ? parts[1] : queryFeature)
    }
}

func openNovagramSettings(context: AccountContext, feature: String?) {
    if feature == "jobs" {
        if NovagramJobSearchAvailability.isEnabled {
            NovagramHooks.shared.openJobSearch(context, nil)
        }
        return
    }
    let navigation = context.bindings.rootNavigation()
    let controller = NovagramSettingsController(context)
    navigation.push(controller)
    guard let feature = feature?.replacingOccurrences(of: "_", with: "-") else {
        return
    }
    switch feature {
    case "about":
        navigation.push(NovagramAboutController(context))
    case "bots":
        navigation.push(NovagramBotsController(context))
    case "tips":
        navigation.push(NovagramTipsController(context))
    case "text-style":
        navigation.push(NovagramTextStyleController(context))
    case "auto-text":
        navigation.push(NovagramAutoTextController(context))
    case "auto-translate":
        navigation.push(NovagramAutoTranslateController(context))
    case "translate-language", "translation-language", "language":
        navigation.push(NovagramTranslationLanguageController(context))
    default:
        controller.focusSlug = feature
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
