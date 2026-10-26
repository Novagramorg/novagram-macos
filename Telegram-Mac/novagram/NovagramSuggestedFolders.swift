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

    /// Feature #37: Create folder for chats where the user is Admin or Owner
    static func createAdminFolder(context: AccountContext, completion: @escaping () -> Void) {
        _ = (context.engine.peers.currentChatListFilters()
             |> take(1)
             |> deliverOnMainQueue).start(next: { filters in
            var nextId: Int32 = 2
            while filters.contains(where: { $0.id == nextId }) {
                nextId += 1
            }

            let data = makeFilterData(categories: [.groups, .channels], excludeRead: false)
            let filter = ChatListFilter.filter(id: nextId, title: ChatFolderTitle(text: "Admin", entities: [], enableAnimations: true), emoticon: "⭐️", data: data)

            var newFilters = filters
            newFilters.append(filter)

            _ = (context.engine.peers.updateChatListFiltersInteractively({ _ in
                return newFilters
            }) |> deliverOnMainQueue).start(completed: {
                completion()
            })
        })
    }
}
