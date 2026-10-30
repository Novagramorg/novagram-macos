//
//  NovagramSettingsController.swift
//  Telegram-Mac
//
//  iOS portasi: submodules/Novagram/ProMessager/Sources/NovagramSettingsController.swift
//
//  Mac uchun Settings → Novagram ekrani. iOS dagi 5 ta section'ni qaytaradi:
//    INTERFACE  — hide folders, stories panel, mutual badge
//    CHAT       — deleted messages, jump-to-first, ghost mode, camera picker
//    MESSAGES   — text style*, auto-text*, auto-translate*, translate button, translation language*
//    VOICE→TEXT — STT enable, recognition language
//    PROTECTION — block foreign numbers, block APK files
//
//  *: sub-controller'lar iOS'da ItemListController orqali ochiladi. Mac uchun ular
//  Wave 5 ga ko'chirilgan — hozir "Coming soon" alert chiqaradi va qiymat
//  UserDefaults'ga yozilmaydi. Settings panel'i o'zi ko'rinadi, toggle'lar
//  ishlaydi va shu UserDefaults'ga yoziladi (consumer kod hozircha o'qimaydi —
//  iOS'da `NovagramSettingsChanged` notification orqali o'qiladi; Mac consumerlar
//  kelajakdagi waves'da ulanadi).
//
//  Storage convention (iOS bilan bir xil):
//    UserDefaults(suiteName: "pro_messager")
//      "hide_folders" Bool, "show_stories" Bool (default true),
//      "show_mutual_contact_symbol" Bool (default true),
//      "show_deleted_messages" Bool, "show_view_first_message" Bool,
//      "show_ghost_mode_button" Bool,
//      "show_translate_messages" Bool (default true),
//      "stt_enabled" Bool (default false), "stt_language" String (default "en-US"),
//      "block_foreign_users" Bool, "block_apk_files" Bool
//

import Cocoa
import TGUIKit
import TelegramCore
import Localization
import SwiftSignalKit
import Postbox
import ThemeSettings
import ColorPalette
import NovagramCore

// MARK: - Storage facade

private let novagramDefaults = UserDefaults(suiteName: "pro_messager")

private enum NovagramDefaultsKey {
    static let hideFolders                = "hide_folders"
    static let showStories                = "show_stories"
    static let showMutualContactSymbol    = "show_mutual_contact_symbol"
    static let showDeletedMessages        = "show_deleted_messages"
    static let showViewFirstMessage       = "show_view_first_message"
    static let showGhostMode              = "show_ghost_mode_button"
    static let ghostModeActive            = "is_ghost_mode_active"
    static let showTranslateMessages      = "show_translate_messages"
    static let textStyle                  = "text_style"
    static let autoTextEnabled            = "auto_text_enabled"
    static let autoTranslateEnabled       = "auto_translate_enabled"
    static let sttEnabled                 = "stt_enabled"
    static let sttLanguage                = "stt_language"
    static let blockForeignUsers          = "block_foreign_users"
    static let askBeforeSendVoice         = "ask_before_send_voice"
    static let askBeforeSendSticker       = "ask_before_send_sticker"
    static let unreadReminderEnabled      = "unread_reminder_enabled"
    static let autoApproveJoinRequests    = NovagramAutoApproveManager.defaultsKey
    static let unlimitedFolders           = "unlimited_folders"
    static let adminFolders               = "fenix_admin_folders"
    static let editedHistoryEnabled       = "edited_history_enabled"
    static let roundVideoFromGallery      = "round_video_from_gallery"
    static let forwardHideNames           = "forward_hide_names"
    static let autoStickerEnabled         = "auto_sticker_enabled"
    static let heartEffectEnabled         = "heart_effect_enabled"
    static let foldersPromptEnabled       = "fenix_features_folders_prompt_enabled"
    static let storyUnlockEnabled         = "fenix_story_unlock_enabled"
    static let translateChatsUnlock       = "fenix_translate_chats_unlock"
    static let translateConfirmEnabled    = "translate_confirm_enabled"
    static let voiceTranslateEnabled      = "voice_translate_enabled"
    static let autoDownloadDisabled       = "auto_download_disabled"
    static let whiteThemeAccentEnabled    = "white_theme_accent_enabled"
    static let channelHistoryButton       = "fenix_channel_history_button"
    static let unlimitedPins              = "unlimited_pins"
    static let callRecording              = NovagramCallRecordingSettings.enabledKey
    static let callRecordingAuto          = NovagramCallRecordingSettings.autoKey
    static let callDataSaving             = NovagramCallRecordingSettings.dataSavingKey
}

private struct NovagramSettingsState: Equatable {
    var hideFolders: Bool
    var showStories: Bool
    var showMutualContactSymbol: Bool
    var showDeletedMessages: Bool
    var showViewFirstMessage: Bool
    var showGhostMode: Bool
    var ghostModeActive: Bool
    var showTranslateMessages: Bool
    var textStyle: String
    var autoTextEnabled: Bool
    var autoTranslateEnabled: Bool
    var sttEnabled: Bool
    var sttLanguage: String
    var blockForeignUsers: Bool
    var askBeforeSendVoice: Bool
    var askBeforeSendSticker: Bool
    var unreadReminderEnabled: Bool
    var autoApproveJoinRequests: Bool
    var unlimitedFolders: Bool
    var adminFolders: Bool
    var editedHistoryEnabled: Bool
    var roundVideoFromGallery: Bool
    var forwardHideNames: Bool
    var autoStickerEnabled: Bool
    var heartEffectEnabled: Bool
    var foldersPromptEnabled: Bool
    var storyUnlockEnabled: Bool
    var translateChatsUnlock: Bool
    var translateConfirmEnabled: Bool
    var voiceTranslateEnabled: Bool
    var reminderMinutes: Int
    var reminderSound: String
    var autoDownloadDisabled: Bool
    var whiteThemeAccentEnabled: Bool
    var folderStyle: String
    var channelHistoryButton: Bool
    var unlimitedPins: Bool
    // Feature #46: derived from the keychain (source of truth), NOT novagramDefaults.
    var chatLockMasterEnabled: Bool
    // NovagramProxy opt-in — derived from NovagramAutoProxyManager (owns the "pro_messager" key).
    var novagramProxyEnabled: Bool
    // Hidden "Remove all ads" section: filled from NovagramAdsGate.uiState, not from defaults.
    var adsRevealed: Bool = false
    var showAds: Bool = true
    // The other Developer switches: filled from NovagramDeveloperFlags.
    var currencyRatesView: Bool = false
    var adsPanel: Bool = false
    var stickerPackSave: Bool = false
    var devJobSearch: Bool = false
    var adEventsOff: Bool = false
    var callRecording: Bool = false
    var callRecordingFolder: String? = nil
    var callRecordingAuto: Bool = false
    var callDataSaving: Bool = false
    // Which Developer switches show: filled from NovagramDeveloperRole.
    var developerRole: NovagramDeveloperRole = .developer

    static func load() -> NovagramSettingsState {
        let d = novagramDefaults
        return NovagramSettingsState(
            hideFolders: d?.bool(forKey: NovagramDefaultsKey.hideFolders) ?? false,
            showStories: d?.object(forKey: NovagramDefaultsKey.showStories) as? Bool ?? true,
            showMutualContactSymbol: d?.object(forKey: NovagramDefaultsKey.showMutualContactSymbol) as? Bool ?? true,
            showDeletedMessages: d?.bool(forKey: NovagramDefaultsKey.showDeletedMessages) ?? false,
            showViewFirstMessage: d?.bool(forKey: NovagramDefaultsKey.showViewFirstMessage) ?? false,
            showGhostMode: d?.bool(forKey: NovagramDefaultsKey.showGhostMode) ?? false,
            ghostModeActive: d?.bool(forKey: NovagramDefaultsKey.ghostModeActive) ?? false,
            showTranslateMessages: d?.object(forKey: NovagramDefaultsKey.showTranslateMessages) as? Bool ?? true,
            textStyle: d?.string(forKey: NovagramDefaultsKey.textStyle) ?? "none",
            autoTextEnabled: d?.bool(forKey: NovagramDefaultsKey.autoTextEnabled) ?? false,
            autoTranslateEnabled: d?.bool(forKey: NovagramDefaultsKey.autoTranslateEnabled) ?? false,
            sttEnabled: d?.object(forKey: NovagramDefaultsKey.sttEnabled) as? Bool ?? false,
            sttLanguage: d?.string(forKey: NovagramDefaultsKey.sttLanguage) ?? "en-US",
            blockForeignUsers: d?.bool(forKey: NovagramDefaultsKey.blockForeignUsers) ?? false,
            askBeforeSendVoice: d?.bool(forKey: NovagramDefaultsKey.askBeforeSendVoice) ?? false,
            askBeforeSendSticker: d?.bool(forKey: NovagramDefaultsKey.askBeforeSendSticker) ?? false,
            unreadReminderEnabled: d?.bool(forKey: NovagramDefaultsKey.unreadReminderEnabled) ?? false,
            autoApproveJoinRequests: NovagramAutoApproveManager.shared.isEnabled,
            unlimitedFolders: d?.bool(forKey: NovagramDefaultsKey.unlimitedFolders) ?? false,
            adminFolders: NovagramAdminFoldersManager.isEnabled,
            editedHistoryEnabled: d?.object(forKey: NovagramDefaultsKey.editedHistoryEnabled) as? Bool ?? true,
            roundVideoFromGallery: d?.bool(forKey: NovagramDefaultsKey.roundVideoFromGallery) ?? false,
            forwardHideNames: d?.bool(forKey: NovagramDefaultsKey.forwardHideNames) ?? false,
            autoStickerEnabled: d?.bool(forKey: NovagramDefaultsKey.autoStickerEnabled) ?? false,
            heartEffectEnabled: d?.bool(forKey: NovagramDefaultsKey.heartEffectEnabled) ?? false,
            foldersPromptEnabled: d?.bool(forKey: NovagramDefaultsKey.foldersPromptEnabled) ?? false,
            storyUnlockEnabled: d?.bool(forKey: NovagramDefaultsKey.storyUnlockEnabled) ?? false,
            translateChatsUnlock: d?.bool(forKey: NovagramDefaultsKey.translateChatsUnlock) ?? false,
            translateConfirmEnabled: d?.bool(forKey: NovagramDefaultsKey.translateConfirmEnabled) ?? false,
            voiceTranslateEnabled: d?.bool(forKey: NovagramDefaultsKey.voiceTranslateEnabled) ?? false,
            reminderMinutes: NovagramUnreadReminderManager.shared.intervalMinutes,
            reminderSound: NovagramUnreadReminderManager.shared.soundKey,
            autoDownloadDisabled: d?.bool(forKey: NovagramDefaultsKey.autoDownloadDisabled) ?? false,
            whiteThemeAccentEnabled: d?.bool(forKey: NovagramDefaultsKey.whiteThemeAccentEnabled) ?? false,
            folderStyle: NovagramFolderStyle.current,
            channelHistoryButton: d?.bool(forKey: NovagramDefaultsKey.channelHistoryButton) ?? false,
            unlimitedPins: d?.bool(forKey: NovagramDefaultsKey.unlimitedPins) ?? false,
            chatLockMasterEnabled: NovagramChatPincodeManager.shared.isMasterEnabled(),
            novagramProxyEnabled: NovagramAutoProxyManager.shared.isEnabled,
            callRecording: NovagramCallRecordingSettings.isStoredEnabled,
            callRecordingFolder: NovagramCallRecordingSettings.folderDisplayPath,
            callRecordingAuto: NovagramCallRecordingSettings.isAutoStored,
            callDataSaving: NovagramCallRecordingSettings.isDataSavingEnabled
        )
    }
}

// MARK: - Arguments

private final class NovagramSettingsArguments {
    let context: AccountContext
    let updateBool: (String, Bool) -> Void
    let pickSTTLanguage: () -> Void
    let openSubController: (String) -> Void   // "text_style" | "auto_text" | "auto_translate" | "translate_language"
    let updateChatLockMaster: (Bool) -> Void  // #46: bespoke ON→set-master / OFF→confirm+wipe flow
    let updateNovagramProxy: (Bool) -> Void   // NovagramProxy opt-in → probe + enable/disable

    init(
        context: AccountContext,
        updateBool: @escaping (String, Bool) -> Void,
        pickSTTLanguage: @escaping () -> Void,
        openSubController: @escaping (String) -> Void,
        updateChatLockMaster: @escaping (Bool) -> Void,
        updateNovagramProxy: @escaping (Bool) -> Void
    ) {
        self.context = context
        self.updateBool = updateBool
        self.pickSTTLanguage = pickSTTLanguage
        self.openSubController = openSubController
        self.updateChatLockMaster = updateChatLockMaster
        self.updateNovagramProxy = updateNovagramProxy
    }
}

// MARK: - Entries

private enum NovagramEntryId: Hashable {
    case section(Int)
    case header(Int)
    case topTips
    case topAbout
    case interfaceHideFolders, interfaceStories, interfaceMutual, interfaceUnlimitedPins, interfaceFooter
    case chatDeleted, chatEditedHistory, chatFirstMessage, chatGhostActive, chatGhost, chatRoundVideo, chatForwardHideNames, chatFooter
    case messagingTextStyle, messagingAutoText, messagingAutoTranslate, messagingTranslateToggle, messagingTranslateLang, messagingTranslateConfirm, messagingAskVoice, messagingAskSticker, messagingAutoSticker, messagingHeartEffect, messagingFooter
    case sttEnabled, sttLanguage, sttVoiceTranslate
    case protectionChatLock, protectionProxy, protectionForeign, protectionAutoDownload, protectionFooter
    case appearanceAccent, appearanceFooter
    case remindersUnread, remindersTime, remindersSound, autoApproveJoin, autoUnlimitedFolders, actionSuggestedFolders, autoFoldersPrompt, actionAdminFolder, autoFolderStyle, autoChannelHistory, autoStoryUnlock, autoTranslateChats, actionShareLink, autoFooter
    case adsRemoveAll, devAdEventsOff, devCurrencyRates, devAdsPanel, devStickerPackSave, devJobSearch, devFooter
    case callRecording, callRecordingFolder, callRecordingFooter, callRecordingAuto, callRecordingList, callDataSaving
}

// iOS 1:1 — har bir row uchun rangli kvadrat ikonka (NovagramIconColor + SF Symbol).
private func novagramSettingsRowIcon(_ id: NovagramEntryId) -> CGImage? {
    let map: (String, NovagramIconColor)?
    switch id {
    case .topAbout:                 map = ("info.circle.fill", .blue)
    case .topTips:                  map = ("sparkles", .gold)
    case .interfaceHideFolders:     map = ("folder.badge.minus", .lightBlue)
    case .interfaceStories:         map = ("circle.dashed", .violet)
    case .interfaceMutual:          map = ("person.2.fill", .blue)
    case .interfaceUnlimitedPins:   map = ("pin.fill", .orange)
    case .chatDeleted:              map = ("trash.fill", .red)
    case .chatFirstMessage:         map = ("arrow.up.to.line", .blue)
    case .chatGhostActive:          map = ("eye.slash.fill", .gray)
    case .chatGhost:                map = ("eye.slash", .gray)
    case .chatEditedHistory:        map = ("clock.arrow.circlepath", .blue)
    case .chatRoundVideo:           map = ("video.circle.fill", .violet)
    case .chatForwardHideNames:     map = ("arrowshape.turn.up.right.fill", .teal)
    case .messagingAutoSticker:     map = ("face.smiling", .orange)
    case .messagingHeartEffect:     map = ("heart.fill", .red)
    case .messagingTranslateConfirm: map = ("questionmark.bubble.fill", .pink)
    case .sttVoiceTranslate:        map = ("waveform.badge.plus", .teal)
    case .autoFoldersPrompt:        map = ("folder.badge.questionmark", .lightBlue)
    case .autoStoryUnlock:          map = ("arrow.down.circle.fill", .violet)
    case .actionShareLink:          map = ("link", .blue)
    case .autoFolderStyle:          map = ("square.grid.2x2.fill", .teal)
    case .autoChannelHistory:       map = ("list.bullet.rectangle.fill", .orange)
    case .autoTranslateChats:       map = ("character.bubble", .pink)
    case .messagingTextStyle:       map = ("textformat", .purple)
    case .messagingAutoText:        map = ("text.append", .teal)
    case .messagingAutoTranslate:   map = ("globe", .pink)
    case .messagingTranslateToggle: map = ("character.bubble.fill", .pink)
    case .messagingTranslateLang:   map = ("character.book.closed.fill", .lightBlue)
    case .messagingAskVoice:        map = ("mic.badge.plus", .orange)
    case .messagingAskSticker:      map = ("face.smiling.inverse", .gold)
    case .sttEnabled:               map = ("mic.fill", .red)
    case .sttLanguage:              map = ("globe", .blue)
    case .protectionChatLock:       map = ("lock.shield.fill", .green)
    case .protectionProxy:          map = ("network.badge.shield.half.filled", .green)
    case .protectionForeign:        map = ("person.crop.circle.badge.xmark", .orange)
    case .protectionAutoDownload:   map = ("arrow.down.circle.dotted", .gray)
    case .appearanceAccent:         map = ("paintpalette.fill", .blue)
    case .remindersUnread:          map = ("bell.badge.fill", .red)
    case .remindersTime:            map = ("clock.fill", .blue)
    case .remindersSound:           map = ("speaker.wave.2.fill", .pink)
    case .autoApproveJoin:          map = ("person.crop.circle.badge.checkmark", .green)
    case .autoUnlimitedFolders:     map = ("infinity", .purple)
    case .actionSuggestedFolders:   map = ("folder.badge.plus", .blue)
    case .actionAdminFolder:        map = ("star.circle.fill", .gold)
    case .adsRemoveAll:             map = ("megaphone.fill", .orange)
    case .devCurrencyRates:         map = ("dollarsign.circle.fill", .green)
    case .devAdsPanel:              map = ("rectangle.stack.badge.person.crop.fill", .purple)
    case .devStickerPackSave:       map = ("square.and.arrow.down.on.square.fill", .orange)
    case .devJobSearch:             map = ("briefcase.fill", .orange)
    case .devAdEventsOff:           map = ("eye.slash.circle.fill", .red)
    case .callRecording:            map = ("record.circle", .red)
    case .callRecordingFolder:      map = ("folder.fill", .blue)
    case .callRecordingAuto:        map = ("record.circle.fill", .orange)
    case .callRecordingList:        map = ("waveform", .red)
    case .callDataSaving:           map = ("antenna.radiowaves.left.and.right", .green)
    default:                        map = nil
    }
    guard let (symbol, color) = map else { return nil }
    return novagramSettingsIcon(systemName: symbol, color: color)
}

private enum NovagramEntry: Comparable, Identifiable {
    case section(Int)
    case header(Int, NovagramEntryId, String)
    case toggle(Int, NovagramEntryId, String, String?, Bool, GeneralViewType, String /* defaultsKey */)
    case chatLockToggle(Int, NovagramEntryId, String, String?, Bool, GeneralViewType)
    case novagramProxyToggle(Int, NovagramEntryId, String, String?, Bool, GeneralViewType)
    case disclosurePlaceholder(Int, NovagramEntryId, String, String, GeneralViewType, String /* subKey */)
    case disclosureSTTLanguage(Int, NovagramEntryId, String, String, GeneralViewType)
    case action(Int, NovagramEntryId, String, String?, GeneralViewType, () -> Void)
    case adsToggle(Int, NovagramEntryId, String, String?, Bool, GeneralViewType)
    case developerToggle(Int, NovagramEntryId, String, String?, Bool, GeneralViewType)
    case footer(Int, NovagramEntryId, String)

    var stableId: AnyHashable {
        switch self {
        case let .section(id):                       return NovagramEntryId.section(id)
        case let .header(_, id, _):                  return id
        case let .toggle(_, id, _, _, _, _, _):      return id
        case let .chatLockToggle(_, id, _, _, _, _): return id
        case let .novagramProxyToggle(_, id, _, _, _, _): return id
        case let .disclosurePlaceholder(_, id, _, _, _, _): return id
        case let .disclosureSTTLanguage(_, id, _, _, _): return id
        case let .action(_, id, _, _, _, _):         return id
        case let .adsToggle(_, id, _, _, _, _):      return id
        case let .developerToggle(_, id, _, _, _, _): return id
        case let .footer(_, id, _):                  return id
        }
    }

    var sortIndex: Int {
        switch self {
        case let .section(id): return id * 1000
        case let .header(idx, _, _): return idx
        case let .toggle(idx, _, _, _, _, _, _): return idx
        case let .chatLockToggle(idx, _, _, _, _, _): return idx
        case let .novagramProxyToggle(idx, _, _, _, _, _): return idx
        case let .disclosurePlaceholder(idx, _, _, _, _, _): return idx
        case let .disclosureSTTLanguage(idx, _, _, _, _): return idx
        case let .action(idx, _, _, _, _, _): return idx
        case let .adsToggle(idx, _, _, _, _, _): return idx
        case let .developerToggle(idx, _, _, _, _, _): return idx
        case let .footer(idx, _, _): return idx
        }
    }

    static func < (lhs: NovagramEntry, rhs: NovagramEntry) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

    static func == (lhs: NovagramEntry, rhs: NovagramEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.section(l), .section(r)): return l == r
        case let (.header(l1, l2, l3), .header(r1, r2, r3)): return l1 == r1 && l2 == r2 && l3 == r3
        case let (.toggle(l1, l2, l3, l4, l5, l6, l7), .toggle(r1, r2, r3, r4, r5, r6, r7)):
            return l1 == r1 && l2 == r2 && l3 == r3 && l4 == r4 && l5 == r5 && l6 == r6 && l7 == r7
        case let (.chatLockToggle(l1, l2, l3, l4, l5, l6), .chatLockToggle(r1, r2, r3, r4, r5, r6)):
            return l1 == r1 && l2 == r2 && l3 == r3 && l4 == r4 && l5 == r5 && l6 == r6
        case let (.novagramProxyToggle(l1, l2, l3, l4, l5, l6), .novagramProxyToggle(r1, r2, r3, r4, r5, r6)):
            return l1 == r1 && l2 == r2 && l3 == r3 && l4 == r4 && l5 == r5 && l6 == r6
        case let (.disclosurePlaceholder(l1, l2, l3, l4, l5, l6), .disclosurePlaceholder(r1, r2, r3, r4, r5, r6)):
            return l1 == r1 && l2 == r2 && l3 == r3 && l4 == r4 && l5 == r5 && l6 == r6
        case let (.disclosureSTTLanguage(l1, l2, l3, l4, l5), .disclosureSTTLanguage(r1, r2, r3, r4, r5)):
            return l1 == r1 && l2 == r2 && l3 == r3 && l4 == r4 && l5 == r5
        case let (.action(l1, l2, l3, l4, l5, _), .action(r1, r2, r3, r4, r5, _)):
            return l1 == r1 && l2 == r2 && l3 == r3 && l4 == r4 && l5 == r5
        case let (.footer(l1, l2, l3), .footer(r1, r2, r3)): return l1 == r1 && l2 == r2 && l3 == r3
        case let (.adsToggle(l1, l2, l3, l4, l5, l6), .adsToggle(r1, r2, r3, r4, r5, r6)):
            return l1 == r1 && l2 == r2 && l3 == r3 && l4 == r4 && l5 == r5 && l6 == r6
        case let (.developerToggle(l1, l2, l3, l4, l5, l6), .developerToggle(r1, r2, r3, r4, r5, r6)):
            return l1 == r1 && l2 == r2 && l3 == r3 && l4 == r4 && l5 == r5 && l6 == r6
        default: return false
        }
    }

    func item(_ arguments: NovagramSettingsArguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case .section:
            return GeneralRowItem(initialSize, height: 20, stableId: stableId, viewType: .separator)
        case let .header(_, _, text):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: .textTopItem)
        case let .toggle(_, entryId, title, subtitle, value, viewType, key):
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: title,
                icon: novagramSettingsRowIcon(entryId),
                description: subtitle,
                type: .switchable(value),
                viewType: viewType,
                action: {
                    arguments.updateBool(key, !value)
                },
                // Story saving asks first, so its switch must not flip before the user confirms.
                autoswitch: key != NovagramDefaultsKey.storyUnlockEnabled,
                menuItems: novagramSettingsLinkMenu(entryId, arguments: arguments)
            )
        case let .chatLockToggle(_, entryId, title, subtitle, value, viewType):
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: title,
                icon: novagramSettingsRowIcon(entryId),
                description: subtitle,
                type: .switchable(value),
                viewType: viewType,
                action: {
                    arguments.updateChatLockMaster(!value)
                },
                // The row's true value comes from the keychain and only flips on sheet success.
                // Without autoswitch:false the switch optimistically snaps ON on tap and, if the
                // user dismisses the Set-Pincode sheet with X, never reconciles back to OFF.
                autoswitch: false,
                menuItems: novagramSettingsLinkMenu(entryId, arguments: arguments)
            )
        case let .novagramProxyToggle(_, entryId, title, subtitle, value, viewType):
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: title,
                icon: novagramSettingsRowIcon(entryId),
                description: subtitle,
                type: .switchable(value),
                viewType: viewType,
                action: {
                    arguments.updateNovagramProxy(!value)
                },
                menuItems: novagramSettingsLinkMenu(entryId, arguments: arguments)
            )
        case let .disclosurePlaceholder(_, entryId, title, label, viewType, subKey):
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: title,
                icon: novagramSettingsRowIcon(entryId),
                type: .nextContext(label),
                viewType: viewType,
                action: {
                    arguments.openSubController(subKey)
                },
                menuItems: novagramSettingsLinkMenu(entryId, arguments: arguments)
            )
        case let .disclosureSTTLanguage(_, entryId, title, label, viewType):
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: title,
                icon: novagramSettingsRowIcon(entryId),
                type: .nextContext(label),
                viewType: viewType,
                action: {
                    arguments.pickSTTLanguage()
                },
                menuItems: novagramSettingsLinkMenu(entryId, arguments: arguments)
            )
        case let .action(_, entryId, title, subtitle, viewType, handler):
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: title,
                icon: novagramSettingsRowIcon(entryId),
                description: subtitle,
                type: .next,
                viewType: viewType,
                action: handler,
                menuItems: novagramSettingsLinkMenu(entryId, arguments: arguments)
            )
        case let .adsToggle(_, entryId, title, subtitle, value, viewType):
            // `value` is the switch state (ON = ads removed), so the new `showAds` is the old switch state.
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: title,
                icon: novagramSettingsRowIcon(entryId),
                description: subtitle,
                type: .switchable(value),
                viewType: viewType,
                action: {
                    NovagramAdsGate.setShowAds(value)
                }
            )
        case let .developerToggle(_, entryId, title, subtitle, value, viewType):
            return GeneralInteractedRowItem(
                initialSize, stableId: stableId,
                name: title,
                icon: novagramSettingsRowIcon(entryId),
                description: subtitle,
                type: .switchable(value),
                viewType: viewType,
                action: {
                    switch entryId {
                    case .devCurrencyRates:
                        NovagramDeveloperFlags.isCurrencyRatesViewEnabled = !value
                    case .devAdsPanel:
                        NovagramDeveloperFlags.isAdsPanelEnabled = !value
                    case .devStickerPackSave:
                        NovagramDeveloperFlags.isStickerPackSaveEnabled = !value
                    case .devAdEventsOff:
                        NovagramDeveloperFlags.isAdEventsOff = !value
                    case .devJobSearch:
                        NovagramDeveloperFlags.isJobSearchEnabled = !value
                    default:
                        break
                    }
                }
            )
        case let .footer(_, _, text):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: .textBottomItem)
        }
    }
}

private func novagramSettingsEntries(state: NovagramSettingsState, l10n: NovagramL10n, arguments: NovagramSettingsArguments) -> [NovagramEntry] {
    var entries: [NovagramEntry] = []
    var idx = 0

    func next() -> Int { idx += 1; return idx }
    var sectionId = 0

    // ─── FENIX PRO (top) ───
    entries.append(.section(sectionId)); sectionId += 1
    // Novagram Bots lives in the main Settings list (as on iOS), not here.
    entries.append(.disclosurePlaceholder(next(), .topAbout, l10n.about_rowTitle, "", .singleItem, "about"))

    // ─── INTERFACE ───
    entries.append(.section(sectionId)); sectionId += 1
    entries.append(.header(next(), .header(1), l10n.settings_section_interface))
    entries.append(.toggle(next(), .interfaceHideFolders, l10n.settings_interface_hideFolders_title, l10n.settings_interface_hideFolders_subtitle, state.hideFolders, .firstItem, NovagramDefaultsKey.hideFolders))
    entries.append(.toggle(next(), .interfaceStories, l10n.settings_interface_stories_title, l10n.settings_interface_stories_subtitle, state.showStories, .innerItem, NovagramDefaultsKey.showStories))
    entries.append(.toggle(next(), .interfaceMutual, l10n.settings_interface_mutualSymbol_title, l10n.settings_interface_mutualSymbol_subtitle, state.showMutualContactSymbol, .innerItem, NovagramDefaultsKey.showMutualContactSymbol))
    entries.append(.toggle(next(), .interfaceUnlimitedPins, l10n.settings_unlimitedPins_title, l10n.settings_unlimitedPins_subtitle, state.unlimitedPins, .lastItem, NovagramDefaultsKey.unlimitedPins))
    entries.append(.footer(next(), .interfaceFooter, l10n.settings_interface_footer))

    // ─── CHAT ───
    entries.append(.section(sectionId)); sectionId += 1
    entries.append(.header(next(), .header(2), l10n.settings_section_chat))
    entries.append(.toggle(next(), .chatDeleted, l10n.settings_chat_deletedMessages_title, nil, state.showDeletedMessages, .firstItem, NovagramDefaultsKey.showDeletedMessages))
    entries.append(.toggle(next(), .chatEditedHistory, l10n.settings_chat_editedHistory_title, l10n.settings_chat_editedHistory_subtitle, state.editedHistoryEnabled, .innerItem, NovagramDefaultsKey.editedHistoryEnabled))
    entries.append(.toggle(next(), .chatFirstMessage, l10n.settings_chat_firstMessage_title, nil, state.showViewFirstMessage, .innerItem, NovagramDefaultsKey.showViewFirstMessage))
    entries.append(.toggle(next(), .chatGhostActive, l10n.settings_chat_ghostActive_title, l10n.settings_chat_ghostActive_subtitle, state.ghostModeActive, .innerItem, NovagramDefaultsKey.ghostModeActive))
    entries.append(.toggle(next(), .chatGhost, l10n.settings_chat_ghost_title, nil, state.showGhostMode, .innerItem, NovagramDefaultsKey.showGhostMode))
    entries.append(.toggle(next(), .chatRoundVideo, l10n.settings_chat_roundVideo_title, l10n.settings_chat_roundVideo_subtitle, state.roundVideoFromGallery, .innerItem, NovagramDefaultsKey.roundVideoFromGallery))
    entries.append(.toggle(next(), .chatForwardHideNames, l10n.settings_chat_forwardHideNames_title, l10n.settings_chat_forwardHideNames_subtitle, state.forwardHideNames, .lastItem, NovagramDefaultsKey.forwardHideNames))
    entries.append(.footer(next(), .chatFooter, l10n.settings_chat_footer))

    // ─── MESSAGES ───
    entries.append(.section(sectionId)); sectionId += 1
    entries.append(.header(next(), .header(3), l10n.settings_section_messaging))
    entries.append(.disclosurePlaceholder(next(), .messagingTextStyle, l10n.settings_messaging_textStyle_title, l10n.textStyle_displayName(state.textStyle), .firstItem, "text_style"))
    let autoLabel = state.autoTextEnabled ? l10n.settings_state_enabled : l10n.settings_state_disabled
    entries.append(.disclosurePlaceholder(next(), .messagingAutoText, l10n.settings_messaging_autoText_title, autoLabel, .innerItem, "auto_text"))
    let trLabel = state.autoTranslateEnabled ? l10n.settings_state_enabled : l10n.settings_state_disabled
    entries.append(.disclosurePlaceholder(next(), .messagingAutoTranslate, l10n.settings_messaging_autoTranslate_title, trLabel, .innerItem, "auto_translate"))
    entries.append(.toggle(next(), .messagingTranslateToggle, l10n.settings_messaging_translateToggle_title, l10n.settings_messaging_translateToggle_subtitle, state.showTranslateMessages, .innerItem, NovagramDefaultsKey.showTranslateMessages))
    entries.append(.disclosurePlaceholder(next(), .messagingTranslateLang, l10n.settings_messaging_translateLanguage_title, "", .innerItem, "translate_language"))
    entries.append(.toggle(next(), .messagingTranslateConfirm, l10n.settings_translateConfirm_title, l10n.settings_translateConfirm_subtitle, state.translateConfirmEnabled, .innerItem, NovagramDefaultsKey.translateConfirmEnabled))
    entries.append(.toggle(next(), .messagingAskVoice, l10n.settings_askVoice_title, l10n.settings_askVoice_subtitle, state.askBeforeSendVoice, .innerItem, NovagramDefaultsKey.askBeforeSendVoice))
    entries.append(.toggle(next(), .messagingAskSticker, l10n.settings_askSticker_title, l10n.settings_askSticker_subtitle, state.askBeforeSendSticker, .innerItem, NovagramDefaultsKey.askBeforeSendSticker))
    entries.append(.toggle(next(), .messagingAutoSticker, l10n.settings_autoSticker_title, l10n.settings_autoSticker_subtitle, state.autoStickerEnabled, .innerItem, NovagramDefaultsKey.autoStickerEnabled))
    entries.append(.toggle(next(), .messagingHeartEffect, l10n.settings_heartEffect_title, l10n.settings_heartEffect_subtitle, state.heartEffectEnabled, .lastItem, NovagramDefaultsKey.heartEffectEnabled))
    entries.append(.footer(next(), .messagingFooter, l10n.settings_messaging_footer))

    // ─── VOICE → TEXT ───
    entries.append(.section(sectionId)); sectionId += 1
    entries.append(.header(next(), .header(4), l10n.settings_section_voice))
    entries.append(.toggle(next(), .sttEnabled, l10n.settings_voice_stt_title, l10n.settings_voice_stt_subtitle, state.sttEnabled, .firstItem, NovagramDefaultsKey.sttEnabled))
    entries.append(.disclosureSTTLanguage(next(), .sttLanguage, l10n.settings_voice_sttLang_title, NovagramL10n.sttLanguageName(for: state.sttLanguage), .innerItem))
    entries.append(.toggle(next(), .sttVoiceTranslate, l10n.settings_voiceTranslate_title, l10n.settings_voiceTranslate_subtitle, state.voiceTranslateEnabled, .lastItem, NovagramDefaultsKey.voiceTranslateEnabled))

    // ─── AUTOMATION & FOLDERS ───
    entries.append(.section(sectionId)); sectionId += 1
    entries.append(.header(next(), .header(5), l10n.settings_section_automation))
    entries.append(.toggle(next(), .remindersUnread, l10n.settings_unreadReminder_title, l10n.settings_unreadReminder_subtitle, state.unreadReminderEnabled, .firstItem, NovagramDefaultsKey.unreadReminderEnabled))
    entries.append(.disclosurePlaceholder(next(), .remindersTime, l10n.reminder_time_title, l10n.reminder_minutesLabel(state.reminderMinutes), .innerItem, "reminder_time"))
    entries.append(.disclosurePlaceholder(next(), .remindersSound, l10n.reminder_sound_title, l10n.reminder_soundName(state.reminderSound), .innerItem, "reminder_sound"))
    entries.append(.toggle(next(), .autoApproveJoin, l10n.settings_autoApprove_title, l10n.settings_autoApprove_subtitle, state.autoApproveJoinRequests, .innerItem, NovagramDefaultsKey.autoApproveJoinRequests))
    entries.append(.toggle(next(), .autoUnlimitedFolders, l10n.settings_unlimitedFolders_title, l10n.settings_unlimitedFolders_subtitle, state.unlimitedFolders, .innerItem, NovagramDefaultsKey.unlimitedFolders))
    entries.append(.action(next(), .actionSuggestedFolders, l10n.settings_suggestedFolders_title, l10n.settings_suggestedFolders_subtitle, .innerItem, {
        NovagramSuggestedFolders.createSuggestedFolders(context: arguments.context, completion: {
            DispatchQueue.main.async {
                alert(for: arguments.context.window, info: l10n.settings_suggestedFolders_done)
            }
        })
    }))
    entries.append(.toggle(next(), .autoFoldersPrompt, l10n.settings_foldersPrompt_title, l10n.settings_foldersPrompt_subtitle, state.foldersPromptEnabled, .innerItem, NovagramDefaultsKey.foldersPromptEnabled))
    entries.append(.toggle(next(), .actionAdminFolder, NovagramAdminFoldersStrings.toggleTitle(langCode: NovagramAdminFoldersManager.langCode), NovagramAdminFoldersStrings.toggleSubtitle(langCode: NovagramAdminFoldersManager.langCode), state.adminFolders, .innerItem, NovagramDefaultsKey.adminFolders))
    entries.append(.disclosurePlaceholder(next(), .autoFolderStyle, l10n.settings_folderStyle_title, l10n.settings_folderStyle_label(state.folderStyle), .innerItem, "folder_style"))
    entries.append(.toggle(next(), .autoChannelHistory, l10n.settings_channelHistory_title, l10n.settings_channelHistory_subtitle, state.channelHistoryButton, .innerItem, NovagramDefaultsKey.channelHistoryButton))
    entries.append(.toggle(next(), .autoStoryUnlock, l10n.settings_storyUnlock_title, l10n.settings_storyUnlock_subtitle, state.storyUnlockEnabled, .innerItem, NovagramDefaultsKey.storyUnlockEnabled))
    entries.append(.toggle(next(), .autoTranslateChats, l10n.settings_translateUnlock_title, l10n.settings_translateUnlock_subtitle, state.translateChatsUnlock, .innerItem, NovagramDefaultsKey.translateChatsUnlock))
    entries.append(.action(next(), .actionShareLink, l10n.settingsLink_shareTitle, nil, .lastItem, {
        novagramShareSettingsLink(NovagramSettingsLink.url(slug: nil), context: arguments.context)
    }))
    entries.append(.footer(next(), .autoFooter, l10n.settings_automationFooter + " " + l10n.settingsLink_hint))

    // ─── PROTECTION ───
    entries.append(.section(sectionId)); sectionId += 1
    entries.append(.header(next(), .header(6), l10n.settings_section_protection))
    entries.append(.chatLockToggle(next(), .protectionChatLock, l10n.chatLock_settingsTitle, l10n.chatLock_settingsSubtitle, state.chatLockMasterEnabled, .firstItem))
    entries.append(.novagramProxyToggle(next(), .protectionProxy, NovagramAutoProxyStrings.toggleTitle(langCode: appCurrentLanguage.languageCode), NovagramAutoProxyStrings.toggleTip(langCode: appCurrentLanguage.languageCode), state.novagramProxyEnabled, .innerItem))
    entries.append(.toggle(next(), .protectionForeign, l10n.settings_protection_foreign_title, l10n.settings_protection_foreign_subtitle, state.blockForeignUsers, .innerItem, NovagramDefaultsKey.blockForeignUsers))
    entries.append(.toggle(next(), .protectionAutoDownload, l10n.settings_autoDownloadOff_title, l10n.settings_autoDownloadOff_subtitle, state.autoDownloadDisabled, .lastItem, NovagramDefaultsKey.autoDownloadDisabled))
    entries.append(.footer(next(), .protectionFooter, l10n.settings_protection_footer))

    // ─── APPEARANCE ───
    entries.append(.section(sectionId)); sectionId += 1
    entries.append(.header(next(), .header(8), l10n.settings_section_appearance))
    entries.append(.toggle(next(), .appearanceAccent, l10n.settings_lightAccent_title, l10n.settings_lightAccent_subtitle, state.whiteThemeAccentEnabled, .singleItem, NovagramDefaultsKey.whiteThemeAccentEnabled))
    entries.append(.footer(next(), .appearanceFooter, l10n.settings_lightAccent_footer))

    // Hidden Developer section, like iOS: shown while revealed by a 20 s hold on the Settings version line.
    if state.adsRevealed {
        entries.append(.section(sectionId)); sectionId += 1
        entries.append(.header(next(), .header(7), l10n.developer_sectionTitle))
        let developerRows: [(item: NovagramDeveloperRole.Switch, entry: (Int, GeneralViewType) -> NovagramEntry)] = [
            (.removeAllAds, { .adsToggle($0, .adsRemoveAll, NovagramAdsGate.toggleTitle, l10n.developer_removeAdsTip, !state.showAds, $1) }),
            (.adEventsOff, { .developerToggle($0, .devAdEventsOff, l10n.developer_adEventsOffTitle, l10n.developer_adEventsOffTip, state.adEventsOff, $1) }),
            (.currencyRatesView, { .developerToggle($0, .devCurrencyRates, l10n.developer_currencyRatesTitle, l10n.developer_currencyRatesTip, state.currencyRatesView, $1) }),
            (.adsPanel, { .developerToggle($0, .devAdsPanel, l10n.developer_adsPanelTitle, l10n.developer_adsPanelTip, state.adsPanel, $1) }),
            (.stickerPackSave, { .developerToggle($0, .devStickerPackSave, l10n.developer_stickerPackSaveTitle, l10n.developer_stickerPackSaveTip, state.stickerPackSave, $1) }),
            (.jobSearch, { .developerToggle($0, .devJobSearch, l10n.developer_jobSearchTitle, l10n.developer_jobSearchTip, state.devJobSearch, $1) }),
            (.callDataSaving, { .toggle($0, .callDataSaving, l10n.callDataSaving_title, l10n.callDataSaving_subtitle, state.callDataSaving, $1, NovagramDefaultsKey.callDataSaving) })
        ]
        let visibleRows = developerRows.filter { state.developerRole.canUse($0.item) }
        for (index, row) in visibleRows.enumerated() {
            entries.append(row.entry(next(), bestGeneralViewType(visibleRows, for: index)))
        }
        entries.append(.footer(next(), .devFooter, l10n.developer_footer))
        if NovagramCallRecordingSettings.isSupported && state.developerRole.canUse(.callRecording) {
            entries.append(.section(sectionId)); sectionId += 1
            entries.append(.toggle(next(), .callRecording, l10n.callRecording_title, l10n.callRecording_subtitle, state.callRecording, state.callRecording ? .firstItem : .singleItem, NovagramDefaultsKey.callRecording))
            if state.callRecording {
                entries.append(.toggle(next(), .callRecordingAuto, l10n.callRecording_auto_title, l10n.callRecording_auto_subtitle, state.callRecordingAuto, .innerItem, NovagramDefaultsKey.callRecordingAuto))
                entries.append(.disclosurePlaceholder(next(), .callRecordingFolder, l10n.callRecording_saveTo, state.callRecordingFolder ?? l10n.callRecording_askEveryTime, .innerItem, "call_recording_folder"))
                entries.append(.disclosurePlaceholder(next(), .callRecordingList, l10n.callRecording_list, "", .lastItem, "call_recordings"))
            }
            entries.append(.footer(next(), .callRecordingFooter, l10n.callRecording_footer))
        }
    }

    // trailing spacer
    entries.append(.section(sectionId))

    return entries
}

// MARK: - Transition

private func prepareNovagramTransition(left: [AppearanceWrapperEntry<NovagramEntry>], right: [AppearanceWrapperEntry<NovagramEntry>], arguments: NovagramSettingsArguments, initialSize: NSSize) -> TableUpdateTransition {
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize)
    }
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
}

// MARK: - Controller

class NovagramSettingsController: TableViewController {

    // Set by a tg://settings/novagrampro/<slug> link: the row to scroll to and highlight once loaded.
    var focusSlug: String?

    private func applyFocusSlug() {
        guard let slug = focusSlug, let entryId = novagramSettingsEntryId(slug: slug) else {
            return
        }
        guard genericView.item(stableId: AnyHashable(entryId)) != nil else {
            return
        }
        focusSlug = nil
        genericView.scroll(to: .center(id: AnyHashable(entryId), innerId: nil, animated: true, focus: .init(focus: true), inset: 0), inset: NSEdgeInsets())
    }

    private let disposable = MetaDisposable()
    private let adsDisposable = MetaDisposable()
    private let developerDisposable = MetaDisposable()
    private let statePromise = ValuePromise(NovagramSettingsState.load(), ignoreRepeated: true)
    private let stateValue = Atomic(value: NovagramSettingsState.load())

    override var defaultBarTitle: String {
        return NovagramL10n.current.settings_title
    }

    override var removeAfterDisapper: Bool {
        return false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let context = self.context
        let window = context.window

        let updateState: ((inout NovagramSettingsState) -> Void) -> Void = { [weak self] mutate in
            guard let self = self else { return }
            let new = self.stateValue.modify { current in
                var s = current
                mutate(&s)
                return s
            }
            self.statePromise.set(new)
        }

        let arguments = NovagramSettingsArguments(
            context: context,
            updateBool: { key, value in
                if key == NovagramDefaultsKey.ghostModeActive {
                    NovagramGhostMode.isActive = value
                } else if key == NovagramDefaultsKey.adminFolders {
                    if value {
                        NovagramAdminFoldersManager.enable(context: context, completion: { outcome in
                            alert(for: window, info: NovagramAdminFoldersStrings.message(for: outcome, langCode: NovagramAdminFoldersManager.langCode))
                        })
                    } else {
                        NovagramAdminFoldersManager.disable(context: context)
                    }
                } else if key == NovagramDefaultsKey.callRecording {
                    NovagramCallRecordingSettings.setEnabled(value)
                    if value {
                        NovagramCallRecordingSettings.chooseFolder(window: window, completion: { _ in
                            updateState { $0.callRecordingFolder = NovagramCallRecordingSettings.folderDisplayPath }
                        })
                    }
                } else if key == NovagramDefaultsKey.storyUnlockEnabled && value {
                    let l10n = NovagramL10n.current
                    verifyAlert(for: window, header: l10n.settings_storyUnlock_warningTitle, information: l10n.settings_storyUnlock_warningText, ok: l10n.settings_storyUnlock_warningConfirm, cancel: l10n.askSend_cancel, successHandler: { _ in
                        novagramDefaults?.set(true, forKey: key)
                        updateState { $0.storyUnlockEnabled = true }
                    })
                    return
                } else {
                    novagramDefaults?.set(value, forKey: key)
                    if key == NovagramDefaultsKey.autoStickerEnabled && !value {
                        NovagramOutgoing.clearAutoSticker()
                    }
                    if key == NovagramDefaultsKey.unlimitedPins && !value {
                        NovagramUnlimitedPins.unpinLocalPins(sharedContext: context.sharedContext)
                    }
                    if key == NovagramDefaultsKey.autoDownloadDisabled {
                        NovagramAutoDownload.apply(disabled: value, sharedContext: context.sharedContext)
                    } else if key == NovagramDefaultsKey.whiteThemeAccentEnabled {
                        NovagramWhiteThemeAccent.apply(enabled: value, accountManager: context.sharedContext.accountManager)
                    }
                    // The send prompt and the dictation translate exclude each other, as on iOS.
                    if value && key == NovagramDefaultsKey.translateConfirmEnabled {
                        novagramDefaults?.set(false, forKey: NovagramDefaultsKey.voiceTranslateEnabled)
                        updateState { $0.voiceTranslateEnabled = false }
                    } else if value && key == NovagramDefaultsKey.voiceTranslateEnabled {
                        novagramDefaults?.set(false, forKey: NovagramDefaultsKey.translateConfirmEnabled)
                        updateState { $0.translateConfirmEnabled = false }
                    }
                }
                updateState { state in
                    switch key {
                    case NovagramDefaultsKey.hideFolders: state.hideFolders = value
                    case NovagramDefaultsKey.showStories: state.showStories = value
                    case NovagramDefaultsKey.showMutualContactSymbol: state.showMutualContactSymbol = value
                    case NovagramDefaultsKey.showDeletedMessages: state.showDeletedMessages = value
                    case NovagramDefaultsKey.showViewFirstMessage: state.showViewFirstMessage = value
                    case NovagramDefaultsKey.showGhostMode: state.showGhostMode = value
                    case NovagramDefaultsKey.ghostModeActive: state.ghostModeActive = value
                    case NovagramDefaultsKey.showTranslateMessages: state.showTranslateMessages = value
                    case NovagramDefaultsKey.sttEnabled: state.sttEnabled = value
                    case NovagramDefaultsKey.blockForeignUsers: state.blockForeignUsers = value
                    case NovagramDefaultsKey.unlimitedFolders: state.unlimitedFolders = value
                    case NovagramDefaultsKey.adminFolders: state.adminFolders = value
                    case NovagramDefaultsKey.editedHistoryEnabled: state.editedHistoryEnabled = value
                    case NovagramDefaultsKey.roundVideoFromGallery: state.roundVideoFromGallery = value
                    case NovagramDefaultsKey.forwardHideNames: state.forwardHideNames = value
                    case NovagramDefaultsKey.autoStickerEnabled: state.autoStickerEnabled = value
                    case NovagramDefaultsKey.heartEffectEnabled: state.heartEffectEnabled = value
                    case NovagramDefaultsKey.foldersPromptEnabled: state.foldersPromptEnabled = value
                    case NovagramDefaultsKey.storyUnlockEnabled: state.storyUnlockEnabled = value
                    case NovagramDefaultsKey.translateChatsUnlock: state.translateChatsUnlock = value
                    case NovagramDefaultsKey.translateConfirmEnabled: state.translateConfirmEnabled = value
                    case NovagramDefaultsKey.voiceTranslateEnabled: state.voiceTranslateEnabled = value
                    case NovagramDefaultsKey.autoDownloadDisabled: state.autoDownloadDisabled = value
                    case NovagramDefaultsKey.whiteThemeAccentEnabled: state.whiteThemeAccentEnabled = value
                    case NovagramDefaultsKey.channelHistoryButton: state.channelHistoryButton = value
                    case NovagramDefaultsKey.unlimitedPins: state.unlimitedPins = value
                    case NovagramDefaultsKey.callRecording: state.callRecording = value
                    case NovagramDefaultsKey.callRecordingAuto: state.callRecordingAuto = value
                    case NovagramDefaultsKey.callDataSaving: state.callDataSaving = value
                    default: break
                    }
                }
                NotificationCenter.default.post(name: NSNotification.Name("NovagramSettingsChanged"), object: nil)
            },
            pickSTTLanguage: { [weak self] in
                guard let self = self else { return }
                let current = self.stateValue.with { $0.sttLanguage }
                self.presentSTTLanguagePicker(currentId: current, window: window) { newId in
                    novagramDefaults?.set(newId, forKey: NovagramDefaultsKey.sttLanguage)
                    updateState { state in
                        state.sttLanguage = newId
                    }
                }
            },
            openSubController: { [weak self] subKey in
                // Wave 5 — AppKit ports of the iOS ItemListController screens.
                // Each push lands on a TableViewController that mirrors the iOS
                // controller for the same key.
                guard let self = self else { return }
                let nav = self.navigationController
                switch subKey {
                case "about":
                    nav?.push(NovagramAboutController(context))
                case "tips":
                    nav?.push(NovagramTipsController(context))
                case "text_style":
                    nav?.push(NovagramTextStyleController(context))
                case "auto_text":
                    nav?.push(NovagramAutoTextController(context))
                case "auto_translate":
                    nav?.push(NovagramAutoTranslateController(context))
                case "translate_language":
                    nav?.push(NovagramTranslationLanguageController(context))
                case "folder_style":
                    let l10n = NovagramL10n.current
                    let current = self.stateValue.with { $0.folderStyle }
                    self.presentChoicePicker(NovagramFolderStyle.options.map { style in
                        (l10n.settings_folderStyle_label(style), style == current, {
                            NovagramFolderStyle.set(style)
                            updateState { $0.folderStyle = style }
                        })
                    }, window: window)
                case "call_recordings":
                    if let controller = makeNovagramCallRecordingsController() {
                        nav?.push(controller)
                    }
                case "call_recording_folder":
                    NovagramCallRecordingSettings.changeFolder(window: window, completion: {
                        updateState { $0.callRecordingFolder = NovagramCallRecordingSettings.folderDisplayPath }
                    })
                case "reminder_time":
                    let l10n = NovagramL10n.current
                    let current = self.stateValue.with { $0.reminderMinutes }
                    self.presentChoicePicker(NovagramUnreadReminderManager.minuteOptions.map { minutes in
                        (l10n.reminder_minutesLabel(minutes), minutes == current, {
                            NovagramUnreadReminderManager.shared.setIntervalMinutes(minutes)
                            updateState { $0.reminderMinutes = minutes }
                        })
                    }, window: window)
                case "reminder_sound":
                    let l10n = NovagramL10n.current
                    let current = self.stateValue.with { $0.reminderSound }
                    self.presentChoicePicker(NovagramReminderSounds.options.map { key in
                        (l10n.reminder_soundName(key), key == current, {
                            NovagramUnreadReminderManager.shared.setSound(key)
                            NovagramReminderSounds.play(key)
                            updateState { $0.reminderSound = key }
                        })
                    }, window: window)
                default:
                    let l10n = NovagramL10n.current
                    alert(for: window, header: l10n.sub_comingSoon_title, info: l10n.sub_comingSoon_message)
                }
            },
            updateChatLockMaster: { enable in
                // #46: master is keychain-backed; the row value comes from isMasterEnabled(),
                // so a cancelled setup reconciles back to OFF on the next state emit.
                if enable {
                    NovagramChatPincode.presentSet(for: window) { code in
                        NovagramChatPincodeManager.shared.setMasterPincode(code)
                        updateState { $0.chatLockMasterEnabled = true }
                    }
                } else {
                    // #46: require the master pincode to turn Chat Lock off (mirrors iOS/web) — a confirm-only
                    // OFF would let anyone with the unlocked app disable the gate and unlock every chat.
                    NovagramChatPincode.presentVerify(for: window,
                        verify: { NovagramChatPincodeManager.shared.verifyMaster($0) },
                        onSuccess: {
                            NovagramChatPincodeManager.shared.disableChatLock()
                            updateState { $0.chatLockMasterEnabled = false }
                        })
                }
            },
            updateNovagramProxy: { enable in
                NovagramAutoProxyManager.shared.setEnabled(enable, accountManager: context.sharedContext.accountManager)
                updateState { $0.novagramProxyEnabled = enable }
            }
        )

        adsDisposable.set((NovagramAdsGate.uiState.get() |> deliverOnMainQueue).start(next: { ads in
            updateState { state in
                state.adsRevealed = ads.revealed
                state.showAds = ads.showAds
            }
        }))

        developerDisposable.set(combineLatest(NovagramDeveloperFlags.currencyRatesViewSignal, NovagramDeveloperFlags.adsPanelSignal, NovagramDeveloperFlags.stickerPackSaveSignal, NovagramDeveloperFlags.adEventsOffSignal, NovagramDeveloperRole.currentSignal, NovagramDeveloperFlags.jobSearchSignal).start(next: { currencyRatesView, adsPanel, stickerPackSave, adEventsOff, developerRole, devJobSearch in
            updateState { state in
                state.currencyRatesView = currencyRatesView
                state.adsPanel = adsPanel
                state.stickerPackSave = stickerPackSave
                state.adEventsOff = adEventsOff
                state.developerRole = developerRole
                state.devJobSearch = devJobSearch
                state.callRecording = NovagramCallRecordingSettings.isStoredEnabled
                state.callRecordingAuto = NovagramCallRecordingSettings.isAutoStored
                state.callDataSaving = NovagramCallRecordingSettings.isDataSavingEnabled
            }
        }))

        let initialSize = self.atomicSize
        let previousEntries = Atomic<[AppearanceWrapperEntry<NovagramEntry>]>(value: [])

        let signal = combineLatest(queue: prepareQueue, statePromise.get(), appearanceSignal)
            |> map { state, appearance -> TableUpdateTransition in
                let l10n = NovagramL10n(languageCode: appCurrentLanguage.languageCode)
                let entries = novagramSettingsEntries(state: state, l10n: l10n, arguments: arguments)
                    .map { AppearanceWrapperEntry(entry: $0, appearance: appearance) }
                let previous = previousEntries.swap(entries)
                return prepareNovagramTransition(left: previous, right: entries, arguments: arguments, initialSize: initialSize.modify { $0 })
            }
            |> deliverOnMainQueue

        disposable.set(signal.start(next: { [weak self] transition in
            self?.genericView.merge(with: transition)
            self?.readyOnce()
            self?.applyFocusSlug()
        }))
    }

    // STT language picker — minimal NSMenu (avoids pulling in extra ActionSheet machinery).
    private func presentSTTLanguagePicker(currentId: String, window: Window, apply: @escaping (String) -> Void) {
        presentChoicePicker(NovagramL10n.sttSupportedLanguages.map { id, name in
            (name, id == currentId, { apply(id) })
        }, window: window)
    }

    // A menu of choices with a check mark on the selected one, shown at the click.
    private func presentChoicePicker(_ choices: [(title: String, selected: Bool, apply: () -> Void)], window: Window) {
        var items: [ContextMenuItem] = []
        for choice in choices {
            let title = choice.selected ? "✓ \(choice.title)" : "    \(choice.title)"
            items.append(ContextMenuItem(title, handler: choice.apply))
        }
        let event = NSApp.currentEvent ?? NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: window.mouseLocationOutsideOfEventStream,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )
        if let event = event {
            ContextMenu.show(items: items, view: self.genericView, event: event)
        }
    }

    deinit {
        disposable.dispose()
        adsDisposable.dispose()
        developerDisposable.dispose()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.removeAllHandlers(for: self)
    }
}

// MARK: - Settings links (iOS NovagramSettingsFeature slugs, same kebab-case values)

private let novagramSettingsSlugs: [(NovagramEntryId, String)] = [
    (.topAbout, "about"),
    (.interfaceHideFolders, "hide-folders"), (.interfaceStories, "stories"), (.interfaceMutual, "mutual-contacts"), (.interfaceUnlimitedPins, "unlimited-pins"),
    (.chatDeleted, "deleted-messages"), (.chatEditedHistory, "edited-history"), (.chatFirstMessage, "first-message"), (.chatGhostActive, "ghost-mode"), (.chatGhost, "ghost-button"),
    (.chatRoundVideo, "round-video"), (.chatForwardHideNames, "forward-hide-names"),
    (.messagingTextStyle, "text-style"), (.messagingAutoText, "auto-text"), (.messagingAutoTranslate, "auto-translate"), (.messagingTranslateToggle, "translate-button"),
    (.messagingTranslateLang, "translate-language"), (.messagingTranslateConfirm, "translate-on-send"), (.messagingAskVoice, "send-confirm"), (.messagingAskSticker, "send-confirm-sticker"),
    (.messagingAutoSticker, "auto-sticker"), (.messagingHeartEffect, "heart-effect"),
    (.sttEnabled, "voice-to-text"), (.sttLanguage, "voice-language"), (.sttVoiceTranslate, "voice-translate"),
    (.remindersUnread, "reminder"), (.remindersTime, "reminder-time"), (.remindersSound, "reminder-sound"),
    (.autoApproveJoin, "auto-accept"), (.autoUnlimitedFolders, "unlimited-folders"), (.actionSuggestedFolders, "recommended-folders"), (.autoFoldersPrompt, "folders-prompt"),
    (.actionAdminFolder, "admin-folders"), (.autoFolderStyle, "folder-style"), (.autoChannelHistory, "channel-history"), (.autoStoryUnlock, "story-saving"),
    (.autoTranslateChats, "translate-entire-chats"), (.actionShareLink, "share-link"),
    (.protectionChatLock, "chat-lock"), (.protectionProxy, "proxy"), (.protectionForeign, "block-foreign"), (.protectionAutoDownload, "auto-download"),
    (.appearanceAccent, "white-accent"),
    (.callRecording, "call-recording"), (.callRecordingFolder, "call-recording-folder"), (.callRecordingAuto, "call-recording-auto"), (.callRecordingList, "call-recordings"), (.callDataSaving, "call-data-saving")
]

private func novagramSettingsSlug(_ id: NovagramEntryId) -> String? {
    return novagramSettingsSlugs.first(where: { $0.0 == id })?.1
}

private func novagramSettingsEntryId(slug: String) -> NovagramEntryId? {
    guard novagramSettingsSlugAllowed(slug) else {
        return nil
    }
    return novagramSettingsSlugs.first(where: { $0.1 == slug })?.0
}

private let novagramCallRecordingSettingsSlugs: Set<String> = ["call-recording", "call-recording-folder", "call-recording-auto"]
private let novagramCallDataSavingSettingsSlug = "call-data-saving"
let novagramCallRecordingsSlug = "call-recordings"

func novagramSettingsSlugAllowed(_ slug: String) -> Bool {
    let role = NovagramDeveloperRole.current
    if novagramCallRecordingSettingsSlugs.contains(slug) || slug == novagramCallRecordingsSlug {
        return NovagramAdsGate.isRevealed && role.canUse(.callRecording) && NovagramCallRecordingSettings.isSupported
    }
    if slug == novagramCallDataSavingSettingsSlug {
        return NovagramAdsGate.isRevealed && role.canUse(.callDataSaving)
    }
    return true
}

func novagramShareSettingsLink(_ link: String, context: AccountContext) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(link, forType: .string)
    showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: context.window)
}

// Right-click on a row: a link straight to that setting (iOS: long press).
private func novagramSettingsLinkMenu(_ id: NovagramEntryId, arguments: NovagramSettingsArguments) -> (() -> [ContextMenuItem])? {
    guard let slug = novagramSettingsSlug(id) else {
        return nil
    }
    let context = arguments.context
    return {
        let l10n = NovagramL10n.current
        let link = NovagramSettingsLink.url(slug: slug)
        return [
            ContextMenuItem(l10n.settingsLink_copy, handler: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
                showModalText(for: context.window, text: l10n.settingsLink_copied)
            }, itemImage: MenuAnimation.menu_copy_link.value),
            ContextMenuItem(l10n.settingsLink_share, handler: {
                showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: context.window)
            }, itemImage: MenuAnimation.menu_share.value)
        ]
    }
}

// MARK: - Side effects of Novagram switches

// iOS "Disable auto-download" (`auto_download_disabled`): turns the app's own auto-download switch
// (Settings → Data and Storage) off, or back on, for every logged-in account.
enum NovagramAutoDownload {
    static func apply(disabled: Bool, sharedContext: SharedAccountContext) {
        _ = (sharedContext.activeAccounts |> take(1) |> deliverOnMainQueue).start(next: { accounts in
            for (_, account, _) in accounts.accounts {
                _ = updateMediaDownloadSettingsInteractively(postbox: account.postbox, {
                    $0.withUpdatedAutomaticDownload(!disabled)
                }).start()
            }
        })
    }

    // An account added later starts with auto-download on; keep it off while the switch is on.
    static func applyIfNeeded(context: AccountContext) {
        guard NovagramSettingsKey.bool(NovagramDefaultsKey.autoDownloadDisabled) else {
            return
        }
        _ = updateMediaDownloadSettingsInteractively(postbox: context.account.postbox, {
            $0.withUpdatedAutomaticDownload(false)
        }).start()
    }
}

// iOS "Unlimited Pins" off: unpin the chats that were pinned only on this Mac, in every logged-in
// account, then forget them (TelegramCore `NovagramLocalPins`).
enum NovagramUnlimitedPins {
    static func unpinLocalPins(sharedContext: SharedAccountContext) {
        _ = (sharedContext.activeAccounts |> take(1) |> deliverOnMainQueue).start(next: { accounts in
            var remaining = accounts.accounts.count
            for (_, account, _) in accounts.accounts {
                _ = novagramTrimPinnedChatsToServerLimit(account: account).start(completed: {
                    DispatchQueue.main.async {
                        remaining -= 1
                        if remaining == 0 {
                            NovagramLocalPins.clearAllAccounts()
                        }
                    }
                })
            }
        })
    }
}

// iOS "Brand accent in light theme" (`white_theme_accent_enabled`): Novagram blue becomes the saved accent
// of the Day and Day Classic themes. Turning it off removes only our accent, a user-picked one stays.
enum NovagramWhiteThemeAccent {
    private static let lightThemes: [TelegramBuiltinTheme] = [.day, .dayClassic]

    static func apply(enabled: Bool, accountManager: AccountManager<TelegramAccountManagerTypes>) {
        let ours = PaletteAccentColor(NovagramBrandColors.lightThemeAccent)
        _ = updateThemeInteractivetly(accountManager: accountManager, f: { settings in
            var accents = settings.accents
            for name in lightThemes {
                let index = accents.firstIndex(where: { $0.name == name && $0.cloud == nil })
                if enabled {
                    let accent = LocalAccentColor(name: name, color: ours, cloud: nil)
                    if let index {
                        accents[index] = accent
                    } else {
                        accents.append(accent)
                    }
                } else if let index, accents[index].color == ours {
                    accents.remove(at: index)
                }
            }
            var updated = ThemePaletteSettings(palette: settings.palette, bubbled: settings.bubbled, fontSize: settings.fontSize, wallpaper: settings.wallpaper, defaultDark: settings.defaultDark, defaultDay: settings.defaultDay, defaultIsDark: settings.defaultIsDark, wallpapers: settings.wallpapers, accents: accents, cloudTheme: settings.cloudTheme, associated: settings.associated, legacyMenu: settings.legacyMenu)
            if settings.cloudTheme == nil, lightThemes.contains(settings.palette.parent) {
                updated = updated.installDefaultAccent()
            }
            return updated
        }).start()
    }
}
