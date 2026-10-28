import Cocoa
import AppIntents
import CoreSpotlight
import Postbox
import TelegramCore
import SwiftSignalKit
import NovagramCore

// Spotlight results and Siri / Shortcuts actions (App Intents, macOS 13+): open a contact's chat or
// profile, send a message after a confirmation, ghost mode, unread count, Novagram Settings.
// Hidden chats and chats under chat lock are never offered.

// MARK: - Opening a contact

enum NovagramContactTarget {
    case chat
    case profile
}

private var novagramPendingSpotlightItem: (AccountRecordId, PeerId)?

private func novagramOpenContact(accountId: AccountRecordId, peerId: PeerId, target: NovagramContactTarget, context: AccountContext) {
    guard !NovagramSpotlightContacts.isExcluded(peerId) else {
        return
    }
    if context.account.id != accountId {
        context.sharedContext.switchToAccount(id: accountId, action: .chat(peerId, necessary: true))
        return
    }
    switch target {
    case .chat:
        navigateToChat(navigation: context.bindings.rootNavigation(), context: context, chatLocation: .peer(peerId))
    case .profile:
        _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)) |> deliverOnMainQueue).start(next: { peer in
            if let peer {
                context.bindings.rootNavigation().push(PeerInfoController(context: context, peer: peer._asPeer()))
            }
        })
    }
    NSApp.activate(ignoringOtherApps: true)
    context.window.makeKeyAndOrderFront(nil)
}

// AppDelegate `application(_:continue:)`: true when the activity was one of our contact items.
func novagramContinueSpotlight(_ userActivity: NSUserActivity, context: AccountContext?) -> Bool {
    guard userActivity.activityType == CSSearchableItemActionType, let identifier = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String, let (accountId, peerId) = NovagramSpotlightContacts.parse(identifier) else {
        return false
    }
    if let context {
        novagramOpenContact(accountId: accountId, peerId: peerId, target: .profile, context: context)
    } else {
        novagramPendingSpotlightItem = (accountId, peerId)
    }
    return true
}

// Account started: Siri learns the contact names for the phrases, and a Spotlight result clicked
// before the app was logged in opens now.
func novagramSpotlightAndSiriDidStart(context: AccountContext) {
    if #available(macOS 14.0, *) {
        NovagramShortcuts.updateAppShortcutParameters()
    }
    guard let (accountId, peerId) = novagramPendingSpotlightItem else {
        return
    }
    novagramPendingSpotlightItem = nil
    Queue.mainQueue().after(0.5, {
        novagramOpenContact(accountId: accountId, peerId: peerId, target: .profile, context: context)
    })
}

// MARK: - App Intents

@available(macOS 14.0, *)
private enum NovagramIntentContext {
    // The app may still be logging in when an intent starts it; wait up to 5 seconds.
    @MainActor
    static func current() async -> AccountContext? {
        for _ in 0 ..< 20 {
            if let context = appDelegate?.currentContext {
                return context
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return appDelegate?.currentContext
    }

    static func first<T>(_ signal: Signal<T, NoError>) async -> T? {
        return await withCheckedContinuation { continuation in
            let resumed = Atomic(value: false)
            _ = (signal |> take(1)).start(next: { value in
                if !resumed.swap(true) {
                    continuation.resume(returning: value)
                }
            }, completed: {
                if !resumed.swap(true) {
                    continuation.resume(returning: nil)
                }
            })
        }
    }

    static func contacts() async -> [NovagramContactEntity] {
        guard let context = await current() else {
            return []
        }
        let accountId = context.account.id
        guard let list = await first(context.engine.data.get(TelegramEngine.EngineData.Item.Contacts.List(includePresences: false))) else {
            return []
        }
        return list.peers.compactMap { peer -> NovagramContactEntity? in
            guard case let .user(user) = peer, !NovagramSpotlightContacts.isExcluded(peer.id) else {
                return nil
            }
            let name = [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
            guard !name.isEmpty else {
                return nil
            }
            return NovagramContactEntity(id: NovagramSpotlightContacts.identifier(accountId: accountId, peerId: peer.id), name: name, username: user.addressName)
        }.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    @MainActor
    static func open(_ contact: NovagramContactEntity, target: NovagramContactTarget) async throws {
        guard let context = await current(), let (accountId, peerId) = NovagramSpotlightContacts.parse(contact.id) else {
            throw NovagramIntentError.notAvailable
        }
        novagramOpenContact(accountId: accountId, peerId: peerId, target: target, context: context)
    }
}

@available(macOS 14.0, *)
enum NovagramIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notAvailable

    var localizedStringResource: LocalizedStringResource {
        return "Novagram is not logged in, or this chat is hidden."
    }
}

@available(macOS 14.0, *)
struct NovagramContactEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Novagram Contact"
    static var defaultQuery = NovagramContactQuery()

    let id: String
    let name: String
    let username: String?

    var displayRepresentation: DisplayRepresentation {
        if let username {
            return DisplayRepresentation(title: "\(name)", subtitle: "@\(username)")
        }
        return DisplayRepresentation(title: "\(name)")
    }
}

@available(macOS 14.0, *)
struct NovagramContactQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [NovagramContactEntity] {
        let wanted = Set(identifiers)
        return await NovagramIntentContext.contacts().filter { wanted.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [NovagramContactEntity] {
        let query = string.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "@", with: "")
        return await NovagramIntentContext.contacts().filter {
            $0.name.lowercased().contains(query) || ($0.username?.lowercased().contains(query) ?? false)
        }
    }

    func suggestedEntities() async throws -> [NovagramContactEntity] {
        return await NovagramIntentContext.contacts()
    }
}

@available(macOS 14.0, *)
struct OpenNovagramChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Chat"
    static var description = IntentDescription("Opens the chat with a Novagram contact.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Contact")
    var contact: NovagramContactEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        try await NovagramIntentContext.open(contact, target: .chat)
        return .result()
    }
}

@available(macOS 14.0, *)
struct OpenNovagramProfileIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Profile"
    static var description = IntentDescription("Opens the profile of a Novagram contact.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Contact")
    var contact: NovagramContactEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        try await NovagramIntentContext.open(contact, target: .profile)
        return .result()
    }
}

@available(macOS 14.0, *)
struct SendNovagramMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Message"
    static var description = IntentDescription("Sends a text message to a Novagram contact after you confirm it.")

    @Parameter(title: "Contact")
    var contact: NovagramContactEntity

    @Parameter(title: "Message")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$text) to \(\.$contact)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return .result(dialog: "The message is empty.")
        }
        guard let context = await NovagramIntentContext.current(), let (accountId, peerId) = NovagramSpotlightContacts.parse(contact.id), accountId == context.account.id, !NovagramSpotlightContacts.isExcluded(peerId) else {
            throw NovagramIntentError.notAvailable
        }
        try await requestConfirmation(result: .result(dialog: "Send “\(message)” to \(contact.name)?"), confirmationActionName: .send)
        let enqueue = enqueueMessages(account: context.account, peerId: peerId, messages: [.message(text: message, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])])
        _ = await NovagramIntentContext.first(enqueue)
        return .result(dialog: "Sent to \(contact.name).")
    }
}

@available(macOS 14.0, *)
struct SetNovagramGhostModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Ghost Mode"
    static var description = IntentDescription("Turns Novagram ghost mode on or off: no read receipts, typing or online status.")

    @Parameter(title: "On")
    var enabled: Bool

    init() {}

    init(enabled: Bool) {
        self.enabled = enabled
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Ghost mode: \(\.$enabled)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Bool> {
        NovagramGhostMode.isActive = enabled
        return .result(value: enabled, dialog: enabled ? "Ghost mode is on." : "Ghost mode is off.")
    }
}

@available(macOS 14.0, *)
struct NovagramUnreadCountIntent: AppIntent {
    static var title: LocalizedStringResource = "Unread Messages"
    static var description = IntentDescription("Tells how many unread messages you have in Novagram.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        guard let context = await NovagramIntentContext.current() else {
            throw NovagramIntentError.notAvailable
        }
        let unread = await NovagramIntentContext.first(renderedTotalUnreadCount(accountManager: context.sharedContext.accountManager, postbox: context.account.postbox))
        let count = Int(unread?.0 ?? 0)
        return .result(value: count, dialog: count == 0 ? "You have no unread messages." : "You have \(count) unread messages.")
    }
}

@available(macOS 14.0, *)
struct OpenNovagramSettingsIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Novagram Settings"
    static var description = IntentDescription("Opens the Novagram Settings screen.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let context = await NovagramIntentContext.current() else {
            throw NovagramIntentError.notAvailable
        }
        openNovagramSettings(context: context, feature: nil)
        return .result()
    }
}

@available(macOS 14.0, *)
struct NovagramShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenNovagramChatIntent(), phrases: [
            "Open \(\.$contact) in \(.applicationName)",
            "Message \(\.$contact) in \(.applicationName)",
            "Open a chat in \(.applicationName)"
        ], shortTitle: "Open Chat", systemImageName: "bubble.left.and.bubble.right")
        AppShortcut(intent: OpenNovagramProfileIntent(), phrases: [
            "Show \(\.$contact) profile in \(.applicationName)",
            "Open a profile in \(.applicationName)"
        ], shortTitle: "Open Profile", systemImageName: "person.crop.circle")
        AppShortcut(intent: SendNovagramMessageIntent(), phrases: [
            "Send a message with \(.applicationName)",
            "Send a \(.applicationName) message"
        ], shortTitle: "Send Message", systemImageName: "paperplane")
        AppShortcut(intent: SetNovagramGhostModeIntent(enabled: true), phrases: [
            "Turn on ghost mode in \(.applicationName)"
        ], shortTitle: "Ghost Mode On", systemImageName: "eye.slash")
        AppShortcut(intent: SetNovagramGhostModeIntent(enabled: false), phrases: [
            "Turn off ghost mode in \(.applicationName)"
        ], shortTitle: "Ghost Mode Off", systemImageName: "eye")
        AppShortcut(intent: NovagramUnreadCountIntent(), phrases: [
            "Unread messages in \(.applicationName)",
            "How many unread messages in \(.applicationName)"
        ], shortTitle: "Unread Messages", systemImageName: "envelope.badge")
        AppShortcut(intent: OpenNovagramSettingsIntent(), phrases: [
            "Open \(.applicationName) settings"
        ], shortTitle: "Novagram Settings", systemImageName: "gearshape")
    }
}
