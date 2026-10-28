//
//  NovagramSuggestedFolders.swift
//  Telegram-Mac
//
//  Features #36, #37: Tavsiya etilgan papkalar va Admin papkalar
//  (Suggested Folders & Admin/Owner Folders)
//

import Foundation
import Cocoa
import Postbox
import TelegramCore
import SwiftSignalKit
import TGUIKit
import Localization
import NovagramCore

final class NovagramSuggestedFolders {

    private static func makeFilterData(categories: ChatListFilterPeerCategories, excludeRead: Bool) -> ChatListFilterData {
        return ChatListFilterData(
            isShared: false,
            hasSharedLinks: false,
            categories: categories,
            excludeMuted: false,
            excludeRead: excludeRead,
            excludeArchived: true,
            includePeers: ChatListFilterIncludePeers(),
            excludePeers: [],
            color: nil
        )
    }

    // iOS "Suggest folders after login": the "Add folders?" alert shows once per install,
    // only while the switch is on. Turning the switch on later still shows it once.
    static func presentFirstLaunchPromptIfNeeded(context: AccountContext) {
        guard NovagramSettingsKey.bool("fenix_features_folders_prompt_enabled") else {
            return
        }
        let defaults = UserDefaults(suiteName: NovagramSettingsKey.suite)
        let doneKey = "fenix_features_firstrun_done"
        guard defaults?.bool(forKey: doneKey) != true else {
            return
        }
        defaults?.set(true, forKey: doneKey)
        let l10n = NovagramL10n.current
        Queue.mainQueue().after(2.5, {
            verifyAlert(for: context.window, header: l10n.foldersPrompt_alertTitle, information: l10n.foldersPrompt_alertText, ok: l10n.foldersPrompt_alertConfirm, cancel: l10n.askSend_cancel, successHandler: { _ in
                createSuggestedFolders(context: context, completion: {})
            })
        })
    }

    /// Feature #36: Create default recommended folders (Personal, Groups, Channels, Bots, Unread)
    static func createSuggestedFolders(context: AccountContext, completion: @escaping () -> Void) {
        _ = (context.engine.peers.currentChatListFilters()
             |> take(1)
             |> deliverOnMainQueue).start(next: { filters in
            let existingTitles = Set(filters.compactMap { filter -> String? in
                switch filter {
                case let .filter(_, title, _, _):
                    return title.text.lowercased()
                case .allChats:
                    return nil
                }
            })
            var newFilters: [ChatListFilter] = filters

            // Helper to find unused ID
            var nextId: Int32 = 2
            while newFilters.contains(where: { $0.id == nextId }) {
                nextId += 1
            }

            // 1. Shaxsiy (Personal)
            if !existingTitles.contains("shaxsiy") && !existingTitles.contains("personal") && !existingTitles.contains("личные") {
                let data = makeFilterData(categories: [.contacts, .nonContacts], excludeRead: false)
                let filter = ChatListFilter.filter(id: nextId, title: ChatFolderTitle(text: "Shaxsiy", entities: [], enableAnimations: true), emoticon: "👤", data: data)
                newFilters.append(filter)
                nextId += 1
            }

            // 2. Guruhlar (Groups)
            if !existingTitles.contains("guruhlar") && !existingTitles.contains("groups") && !existingTitles.contains("группы") {
                let data = makeFilterData(categories: [.groups], excludeRead: false)
                let filter = ChatListFilter.filter(id: nextId, title: ChatFolderTitle(text: "Guruhlar", entities: [], enableAnimations: true), emoticon: "👥", data: data)
                newFilters.append(filter)
                nextId += 1
            }

            // 3. Kanallar (Channels)
            if !existingTitles.contains("kanallar") && !existingTitles.contains("channels") && !existingTitles.contains("каналы") {
                let data = makeFilterData(categories: [.channels], excludeRead: false)
                let filter = ChatListFilter.filter(id: nextId, title: ChatFolderTitle(text: "Kanallar", entities: [], enableAnimations: true), emoticon: "📢", data: data)
                newFilters.append(filter)
                nextId += 1
            }

            // 4. Botlar (Bots)
            if !existingTitles.contains("botlar") && !existingTitles.contains("bots") && !existingTitles.contains("боты") {
                let data = makeFilterData(categories: [.bots], excludeRead: false)
                let filter = ChatListFilter.filter(id: nextId, title: ChatFolderTitle(text: "Botlar", entities: [], enableAnimations: true), emoticon: "🤖", data: data)
                newFilters.append(filter)
                nextId += 1
            }

            // 5. O'qilmagan (Unread)
            if !existingTitles.contains("o'qilmagan") && !existingTitles.contains("unread") && !existingTitles.contains("непрочитанные") {
                let data = makeFilterData(categories: [.contacts, .nonContacts, .groups, .channels, .bots], excludeRead: true)
                let filter = ChatListFilter.filter(id: nextId, title: ChatFolderTitle(text: "O'qilmagan", entities: [], enableAnimations: true), emoticon: "✉️", data: data)
                newFilters.append(filter)
                nextId += 1
            }

            _ = (context.engine.peers.updateChatListFiltersInteractively({ _ in
                return newFilters
            }) |> deliverOnMainQueue).start(completed: {
                completion()
            })
        })
    }
}

// Feature #37, port of the iOS FenixAdminFoldersManager: up to 4 real Telegram folders for the
// groups and channels you own (👑) or admin (🔑), kept in sync on launch, account switch and
// whenever the app becomes active. Same "pro_messager" keys as iOS: "fenix_admin_folders" (toggle)
// and "fenix_admin_folders_map_<accountPeerId>" (category → folder id, -1 = deleted by the user).
// Same sync rules as iOS (membership + default title managed, empty folder removed, a folder the
// user deletes stays deleted until the toggle is turned off and on, leftovers adopted by title,
// previous layouts migrated, toggle off removes only our folders). macOS differences:
//   - a new folder is only created while the account has room under its Telegram folder limit;
//     the server rejects the rest (DIALOG_FILTERS_TOO_MUCH) and such a folder would vanish
//   - the old one-shot macOS "Admin" ⭐️ folder (every group and channel) counts as a previous layout
final class NovagramAdminFoldersManager {

    private static let suiteName = "pro_messager"
    private static let enabledKey = "fenix_admin_folders"
    private static let mapKeyPrefix = "fenix_admin_folders_map_"
    private static let tombstoneId: Int32 = -1

    private enum Category: String, CaseIterable {
        case ownerGroups
        case ownerChannels
        case adminGroups
        case adminChannels

        var emoticon: String {
            switch self {
            case .ownerGroups, .adminGroups: return "👥"
            case .ownerChannels, .adminChannels: return "📢"
            }
        }

        // Telegram folder names are limited to 12 characters, emoji included.
        func title(langCode: String) -> String {
            switch self {
            case .ownerGroups:
                switch langCode {
                case "uz": return "👑 Guruhlar"
                case "ru": return "👑 Группы"
                case "zh": return "👑 群组"
                default: return "👑 Groups"
                }
            case .ownerChannels:
                switch langCode {
                case "uz": return "👑 Kanallar"
                case "ru": return "👑 Каналы"
                case "zh": return "👑 频道"
                default: return "👑 Channels"
                }
            case .adminGroups:
                switch langCode {
                case "uz": return "🔑 Guruhlar"
                case "ru": return "🔑 Группы"
                case "zh": return "🔑 群组"
                default: return "🔑 Groups"
                }
            case .adminChannels:
                switch langCode {
                case "uz": return "🔑 Kanallar"
                case "ru": return "🔑 Каналы"
                case "zh": return "🔑 频道"
                default: return "🔑 Channels"
                }
            }
        }

        var allKnownTitles: [String] {
            var titles: [String] = []
            for code in ["en", "uz", "ru", "zh"] {
                let title = self.title(langCode: code)
                if !titles.contains(title) {
                    titles.append(title)
                }
            }
            return titles
        }
    }

    // Titles of the previous iOS 2-folder layout (👑 Owner + 🔑 Admin).
    private static let legacyLayoutTitles: Set<String> = [
        "👑 Owner", "👑 Egalik", "👑 Владелец",
        "🔑 Admin", "🔑 Админ"
    ]

    // The old macOS one-shot folder: "Admin", ⭐️, every non-archived group and channel.
    private static func isOldMacAdminFolder(_ filter: ChatListFilter) -> Bool {
        if case let .filter(_, title, emoticon, data) = filter {
            return title.text == "Admin" && emoticon == "⭐️" && data.categories == [.groups, .channels] && data.includePeers.peers.isEmpty
        }
        return false
    }

    static var isEnabled: Bool {
        return UserDefaults(suiteName: suiteName)?.bool(forKey: enabledKey) == true
    }

    static var langCode: String {
        let code = appCurrentLanguage.languageCode
        return code.hasPrefix("zh") ? "zh" : code
    }

    // MARK: - Per-account category → folder id map

    private static func mapKey(accountPeerId: PeerId) -> String {
        return "\(mapKeyPrefix)\(accountPeerId.toInt64())"
    }

    private static func storedMap(accountPeerId: PeerId) -> [String: Int32] {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let raw = defaults.dictionary(forKey: mapKey(accountPeerId: accountPeerId)) as? [String: NSNumber]
        else {
            return [:]
        }
        return raw.mapValues { $0.int32Value }
    }

    private static func storeMap(_ map: [String: Int32], accountPeerId: PeerId) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let storeKey = mapKey(accountPeerId: accountPeerId)
        if map.isEmpty {
            defaults.removeObject(forKey: storeKey)
        } else {
            defaults.set(map.mapValues { NSNumber(value: $0) }, forKey: storeKey)
        }
    }

    // MARK: - Global monitor (launch, account switch, app activation)

    private static var monitorActive = false
    private static weak var monitorContext: AccountContext?
    private static var activationObserverInstalled = false
    private static var syncInFlight = false
    private static var lastSyncAt: [Int64: Double] = [:]
    private static let minSyncInterval: Double = 30.0

    static func startGlobalMonitor(context: AccountContext) {
        guard isEnabled else { return }
        installActivationObserverIfNeeded()
        if monitorActive && monitorContext === context { return }

        monitorContext = context
        monitorActive = true
        // small delay so the sync never competes with launch work
        Queue.mainQueue().after(1.5, {
            guard monitorActive, isEnabled, let context = monitorContext else { return }
            sync(context: context, force: false, completion: nil)
        })
    }

    static func stopGlobalMonitor() {
        monitorActive = false
        monitorContext = nil
    }

    // Activation also re-localizes the default titles after a language switch.
    private static func installActivationObserverIfNeeded() {
        guard !activationObserverInstalled else { return }
        activationObserverInstalled = true
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main, using: { _ in
            guard monitorActive, isEnabled, let context = monitorContext else { return }
            sync(context: context, force: false, completion: nil)
        })
    }

    // MARK: - Toggle entry points (settings screen)

    enum EnableOutcome {
        case foldersReady(created: Int, total: Int, waiting: Int, summary: String)
        case nothingToManage
        case noRoom(limit: Int, summary: String)
    }

    static func enable(context: AccountContext, completion: @escaping (EnableOutcome) -> Void) {
        UserDefaults(suiteName: suiteName)?.set(true, forKey: enabledKey)
        // re-enabling is explicit consent to create all folders again, so tombstones go
        let accountPeerId = context.account.peerId
        let cleanedMap = storedMap(accountPeerId: accountPeerId).filter { $0.value != tombstoneId }
        storeMap(cleanedMap, accountPeerId: accountPeerId)

        startGlobalMonitor(context: context)
        sync(context: context, force: true, completion: { result in
            if result.total > 0 {
                completion(.foldersReady(created: result.created, total: result.total, waiting: result.waiting, summary: result.summary))
            } else if result.waiting > 0 {
                completion(.noRoom(limit: result.folderLimit, summary: result.summary))
            } else {
                completion(.nothingToManage)
            }
        })
    }

    static func disable(context: AccountContext) {
        UserDefaults(suiteName: suiteName)?.set(false, forKey: enabledKey)
        stopGlobalMonitor()
        // remove our folders on every logged-in account; each removal reads its ids before the map is cleared
        _ = (context.sharedContext.activeAccounts
        |> take(1)
        |> deliverOnMainQueue).start(next: { active in
            for (_, account, _) in active.accounts {
                removeManagedFolders(engine: TelegramEngine(account: account), accountPeerId: account.peerId)
            }
            if let defaults = UserDefaults(suiteName: suiteName) {
                for storeKey in defaults.dictionaryRepresentation().keys where storeKey.hasPrefix(mapKeyPrefix) {
                    defaults.removeObject(forKey: storeKey)
                }
            }
        })
    }

    private static func removeManagedFolders(engine: TelegramEngine, accountPeerId: PeerId) {
        let managedIds = Set(storedMap(accountPeerId: accountPeerId).values.filter { $0 != tombstoneId })
        storeMap([:], accountPeerId: accountPeerId)
        guard !managedIds.isEmpty else { return }
        _ = engine.peers.updateChatListFiltersInteractively({ filters in
            return filters.filter { filter in
                if case let .filter(id, _, _, _) = filter {
                    return !managedIds.contains(id)
                }
                return true
            }
        }).start()
    }

    // MARK: - Sync

    struct SyncResult {
        var created: Int
        var total: Int
        // categories that have chats but no folder yet because the folder limit is reached
        var waiting: Int
        var folderLimit: Int
        // chats found per category, one "title: count" line each (macOS only, shown in the alert)
        var summary: String
    }

    private static func sync(context: AccountContext, force: Bool, completion: ((SyncResult) -> Void)?) {
        let accountPeerId = context.account.peerId
        let accountKey = accountPeerId.toInt64()
        let now = CFAbsoluteTimeGetCurrent()
        if !force {
            if syncInFlight { return }
            if let last = lastSyncAt[accountKey], now - last < minSyncInterval { return }
        }
        syncInFlight = true
        lastSyncAt[accountKey] = now

        _ = combineLatest(
            queue: Queue.mainQueue(),
            context.engine.messages.chatList(group: .root, count: 1000) |> take(1),
            context.engine.messages.chatList(group: .archive, count: 500) |> take(1),
            context.engine.data.get(
                TelegramEngine.EngineData.Item.Peer.Peer(id: accountPeerId),
                TelegramEngine.EngineData.Item.Configuration.UserLimits(isPremium: false),
                TelegramEngine.EngineData.Item.Configuration.UserLimits(isPremium: true)
            )
        ).start(next: { rootList, archiveList, configuration in
            let (accountPeer, freeLimits, premiumLimits) = configuration
            let isPremium = accountPeer?.isPremium ?? false
            let maxChatsPerFolder = Int(isPremium ? premiumLimits.maxFolderChatsCount : freeLimits.maxFolderChatsCount)
            let maxFolders = Int(isPremium ? premiumLimits.maxFoldersCount : freeLimits.maxFoldersCount)

            // newest chats first, so the per-folder cap keeps the active ones when truncating
            var byCategory: [Category: [PeerId]] = [:]
            for item in (archiveList.items + rootList.items).reversed() {
                guard let peer = item.renderedPeer.chatMainPeer else { continue }
                guard let category = classify(peer: peer._asPeer()) else { continue }
                byCategory[category, default: []].append(peer.id)
            }

            let summary = Category.allCases.map { "\($0.title(langCode: langCode)): \(byCategory[$0]?.count ?? 0)" }.joined(separator: "\n")
            applyToFilters(context: context, accountPeerId: accountPeerId, byCategory: byCategory, maxChats: maxChatsPerFolder, maxFolders: maxFolders, summary: summary, langCode: langCode, completion: completion)
        })
    }

    private static func classify(peer: Peer) -> Category? {
        if let channel = peer as? TelegramChannel {
            guard case .member = channel.participationStatus else { return nil }
            let isOwner = channel.flags.contains(.isCreator)
            guard isOwner || channel.adminRights != nil else { return nil }
            switch channel.info {
            case .broadcast:
                return isOwner ? .ownerChannels : .adminChannels
            case .group:
                return isOwner ? .ownerGroups : .adminGroups
            }
        } else if let group = peer as? TelegramGroup {
            if group.flags.contains(.deactivated) {
                return nil
            }
            guard case .Member = group.membership else { return nil }
            switch group.role {
            case .creator:
                return .ownerGroups
            case .admin:
                return .adminGroups
            case .member:
                return nil
            }
        }
        return nil
    }

    private static func isFolder(_ filter: ChatListFilter) -> Bool {
        if case .filter = filter {
            return true
        }
        return false
    }

    private static func applyToFilters(context: AccountContext, accountPeerId: PeerId, byCategory: [Category: [PeerId]], maxChats: Int, maxFolders: Int, summary: String, langCode: String, completion: ((SyncResult) -> Void)?) {
        let result = Atomic<SyncResult>(value: SyncResult(created: 0, total: 0, waiting: 0, folderLimit: maxFolders, summary: summary))

        _ = (context.engine.peers.updateChatListFiltersInteractively { filters in
            var updated = filters
            var map = storedMap(accountPeerId: accountPeerId)
            var created = 0
            var waiting = 0

            // migrate off a previous layout: folders under map keys that are no longer a category,
            // unmapped folders with a previous-layout title, and the old macOS "Admin" ⭐️ folder
            let validKeys = Set(Category.allCases.map { $0.rawValue })
            var legacyIds = Set<Int32>()
            for (key, id) in map where !validKeys.contains(key) {
                if id != tombstoneId {
                    legacyIds.insert(id)
                }
                map.removeValue(forKey: key)
            }
            let mappedIdsAfterMigration = Set(map.values)
            updated.removeAll(where: { filter in
                if case let .filter(id, title, _, _) = filter {
                    if legacyIds.contains(id) {
                        return true
                    }
                    if !mappedIdsAfterMigration.contains(id) && (legacyLayoutTitles.contains(title.text) || isOldMacAdminFolder(filter)) {
                        return true
                    }
                }
                return false
            })

            var freeSlots = maxFolders - updated.filter(isFolder).count

            for category in Category.allCases {
                let peers = Array((byCategory[category] ?? []).prefix(maxChats))
                let localizedTitle = category.title(langCode: langCode)

                if let mappedId = map[category.rawValue], mappedId == tombstoneId {
                    continue
                }

                if let mappedId = map[category.rawValue] {
                    if let index = updated.firstIndex(where: { $0.id == mappedId }) {
                        if peers.isEmpty {
                            // an empty folder is invalid server-side, so drop it (recreated when needed)
                            updated.remove(at: index)
                            map.removeValue(forKey: category.rawValue)
                            freeSlots += 1
                        } else if case let .filter(id, title, emoticon, data) = updated[index] {
                            var updatedData = data
                            updatedData.includePeers.setPeers(peers)
                            updatedData.excludePeers.removeAll(where: { peers.contains($0) })
                            // follow the app language while the folder keeps one of our default titles
                            var updatedTitle = title
                            if title.text != localizedTitle && category.allKnownTitles.contains(title.text) {
                                updatedTitle = ChatFolderTitle(text: localizedTitle, entities: [], enableAnimations: title.enableAnimations)
                            }
                            if updatedData != data || updatedTitle != title {
                                updated[index] = .filter(id: id, title: updatedTitle, emoticon: emoticon, data: updatedData)
                            }
                        }
                    } else {
                        // the folder we managed is gone: the user deleted it, respect that
                        map[category.rawValue] = tombstoneId
                    }
                    continue
                }

                guard !peers.isEmpty else { continue }

                // adopt a leftover folder with one of our titles instead of creating a duplicate
                let claimedIds = Set(map.values)
                if let index = updated.firstIndex(where: { filter in
                    if case let .filter(id, title, _, _) = filter {
                        return !claimedIds.contains(id) && category.allKnownTitles.contains(title.text)
                    }
                    return false
                }), case let .filter(id, title, emoticon, data) = updated[index] {
                    var updatedData = data
                    updatedData.includePeers.setPeers(peers)
                    updatedData.excludePeers.removeAll(where: { peers.contains($0) })
                    let updatedTitle = ChatFolderTitle(text: localizedTitle, entities: [], enableAnimations: title.enableAnimations)
                    updated[index] = .filter(id: id, title: updatedTitle, emoticon: emoticon, data: updatedData)
                    map[category.rawValue] = id
                    continue
                }

                // the server rejects folders over the limit, so wait for a free slot instead
                guard freeSlots > 0 else {
                    waiting += 1
                    continue
                }

                var includePeers = ChatListFilterIncludePeers()
                includePeers.setPeers(peers)
                let data = ChatListFilterData(
                    isShared: false,
                    hasSharedLinks: false,
                    categories: [],
                    excludeMuted: false,
                    excludeRead: false,
                    excludeArchived: false,
                    includePeers: includePeers,
                    excludePeers: [],
                    color: nil
                )
                let newId = context.engine.peers.generateNewChatListFilterId(filters: updated)
                updated.append(.filter(
                    id: newId,
                    title: ChatFolderTitle(text: localizedTitle, entities: [], enableAnimations: true),
                    emoticon: category.emoticon,
                    data: data
                ))
                map[category.rawValue] = newId
                created += 1
                freeSlots -= 1
            }

            storeMap(map, accountPeerId: accountPeerId)
            _ = result.modify { current in
                var current = current
                current.created = created
                current.total = map.values.filter({ $0 != tombstoneId }).count
                current.waiting = waiting
                return current
            }
            return updated
        }
        |> deliverOnMainQueue).start(next: { _ in
            syncInFlight = false
            completion?(result.with { $0 })
        })
    }
}

// MARK: - Strings (en, uz, ru, zh like iOS FenixAdminFoldersStrings)

enum NovagramAdminFoldersStrings {
    static func toggleTitle(langCode: String) -> String {
        switch langCode {
        case "uz": return "Admin papkalar"
        case "ru": return "Папки админа"
        case "zh": return "管理员分组"
        default:   return "Admin Folders"
        }
    }

    static func toggleSubtitle(langCode: String) -> String {
        switch langCode {
        case "uz": return "Siz ega (👑) yoki admin (🔑) bo'lgan guruh va kanallarni 4 ta avtomatik papkaga ajratib beradi. Huquqlaringiz o'zgarsa papkalar o'z-o'zidan yangilanadi; o'chirilganda papkalar olib tashlanadi."
        case "ru": return "Раскладывает группы и каналы, где вы владелец (👑) или админ (🔑), по 4 автоматическим папкам. Папки обновляются сами при изменении ваших прав; при отключении они удаляются."
        case "zh": return "将你拥有（👑）或管理（🔑）的群组和频道自动归入 4 个分组。你的权限变化时分组会自动更新；关闭后将移除这些分组。"
        default:   return "Sorts the groups and channels you own (👑) or admin (🔑) into 4 automatic folders. They keep updating as your rights change; turning this off removes them."
        }
    }

    static func message(for outcome: NovagramAdminFoldersManager.EnableOutcome, langCode: String) -> String {
        switch outcome {
        case let .foldersReady(created, _, waiting, summary):
            var text = created > 0 ? createdAlert(count: created, langCode: langCode) : upToDateAlert(langCode: langCode)
            if waiting > 0 {
                text += "\n\n" + waitingNote(count: waiting, langCode: langCode)
            }
            return text + "\n\n" + summary
        case .nothingToManage:
            return emptyAlert(langCode: langCode)
        case let .noRoom(limit, summary):
            return noRoomAlert(limit: limit, langCode: langCode) + "\n\n" + summary
        }
    }

    private static func createdAlert(count: Int, langCode: String) -> String {
        switch langCode {
        case "uz": return "\(count) ta papka yaratildi. Admin huquqlaringiz o'zgarganda papkalar avtomatik yangilanib boradi."
        case "ru": return "Создано папок: \(count). Они будут обновляться автоматически при изменении ваших прав."
        case "zh": return "已创建 \(count) 个分组。管理员权限变化时，分组会自动更新。"
        default:   return count == 1 ? "1 folder created. It will keep updating automatically as your admin rights change." : "\(count) folders created. They will keep updating automatically as your admin rights change."
        }
    }

    private static func upToDateAlert(langCode: String) -> String {
        switch langCode {
        case "uz": return "Papkalaringiz allaqachon mavjud — ro'yxatlari yangilab chiqildi."
        case "ru": return "Папки уже существуют — их содержимое обновлено."
        case "zh": return "你的分组已存在，内容已刷新。"
        default:   return "Your folders already exist — their contents have been refreshed."
        }
    }

    private static func emptyAlert(langCode: String) -> String {
        switch langCode {
        case "uz": return "Siz hozircha hech bir guruh yoki kanalda ega yoki admin emassiz. Admin bo'lganingizda papkalar avtomatik paydo bo'ladi."
        case "ru": return "Пока вы не владелец и не админ ни в одной группе или канале. Папки появятся автоматически, как только вы ими станете."
        case "zh": return "你目前还不是任何群组或频道的所有者或管理员。成为所有者或管理员后，分组会自动出现。"
        default:   return "You are not an owner or admin of any group or channel yet. The folders will appear automatically once you become one."
        }
    }

    private static func noRoomAlert(limit: Int, langCode: String) -> String {
        switch langCode {
        case "uz": return "Yangi papka uchun joy yo'q: bu accountda \(limit) tagacha papka bo'lishi mumkin. Bitta papkani o'chirsangiz, admin papkalar avtomatik yaratiladi."
        case "ru": return "Нет места для новых папок: на этом аккаунте можно до \(limit) папок. Удалите одну папку, и папки админа появятся автоматически."
        case "zh": return "没有空间创建新分组：此账号最多可有 \(limit) 个分组。删除一个分组后，管理员分组会自动创建。"
        default:   return "No room for new folders: this account can have up to \(limit) folders. Delete a folder and the admin folders will be created automatically."
        }
    }

    private static func waitingNote(count: Int, langCode: String) -> String {
        switch langCode {
        case "uz": return "Yana \(count) ta papka uchun joy yo'q. Biror papkani o'chirsangiz, ular avtomatik yaratiladi."
        case "ru": return "Ещё \(count) папк(и) ждут свободного места. Удалите папку, и они появятся автоматически."
        case "zh": return "还有 \(count) 个分组因数量上限未创建。删除一个分组后会自动创建。"
        default:   return count == 1 ? "1 more folder is waiting for a free slot. Delete a folder and it will be created automatically." : "\(count) more folders are waiting for a free slot. Delete a folder and they will be created automatically."
        }
    }
}
