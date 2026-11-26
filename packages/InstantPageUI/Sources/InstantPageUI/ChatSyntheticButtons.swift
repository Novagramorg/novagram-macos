import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
import TelegramTheme
import TelegramContext
import TelegramUtils

#if DEBUG

public let chatSyntheticButtonsCommand = "/synthetic_buttons"

public enum SyntheticButtonKind {
    case regular
    case accent
    case success
    case destructive
}

public func syntheticButton(_ text: RichText, kind: SyntheticButtonKind, action: ReplyMarkupButtonAction, isEnabled: Bool = true) -> InstantPageButton {
    let color: ReplyMarkupButton.Style.Color?
    switch kind {
    case .regular:     color = nil
    case .accent:      color = .primary
    case .success:     color = .success
    case .destructive: color = .danger
    }
    return InstantPageButton(text: isEnabled ? text : instantPageDisabledButtonText(text), action: action, color: color)
}

public func syntheticButton(_ label: String, kind: SyntheticButtonKind, action: ReplyMarkupButtonAction, isEnabled: Bool = true) -> InstantPageButton {
    return syntheticButton(.plain(label), kind: kind, action: action, isEnabled: isEnabled)
}

/// Callback buttons deliberately have no corner icon. The payload makes each fixture action distinct.
public func syntheticCallback(_ label: String) -> ReplyMarkupButtonAction {
    return .callback(requiresPassword: false, data: MemoryBuffer(data: Data(label.utf8)))
}

public func syntheticButtonsInstantPage(peerId: PeerId) -> InstantPage {
    let firstParagraph = RichText.concat([
        .plain("Your daily "),
        .textButton(syntheticButton("🏆 challenge", kind: .accent, action: syntheticCallback("challenge"))),
        .plain(" ready! Tap "),
        .textButton(syntheticButton("Play Now", kind: .accent, action: syntheticCallback("Play Now"))),
        .plain(" start, or "),
        .textButton(syntheticButton("Continue", kind: .accent, action: .disabled)),
        .plain(" your last run once you finish today's round.")
    ])

    let secondParagraph = RichText.concat([
        .plain("Need a break? You can "),
        .textButton(syntheticButton("View stats", kind: .regular, action: syntheticCallback("View stats"))),
        .plain(" anytime, or "),
        .textButton(syntheticButton("Claim reward", kind: .regular, action: .disabled)),
        .plain(" after your first win.")
    ])

    let invitationParagraph = RichText.concat([
        .bold(.plain("Ranked match invitation from ")),
        .marked(.fixed(.plain("A L E X"))),
        .plain(" expires in 5 min. "),
        .textButton(syntheticButton("add friend", kind: .success, action: .disabled)),
        .plain(" "),
        .textButton(syntheticButton("block", kind: .destructive, action: .disabled)),
        .plain(" "),
        .textButton(syntheticButton("block", kind: .destructive, action: syntheticCallback("block_enabled"))),
        .plain(" "),
        .textButton(syntheticButton("profile", kind: .regular, action: .disabled)),
        .plain(" "),
        .textButton(syntheticButton("profile", kind: .regular, action: syntheticCallback("profile_enabled")))
    ])

    let estimateParagraph = RichText.concat([
        .plain("Estimate time: 30 min. "),
        .textButton(syntheticButton("add time", kind: .regular, action: syntheticCallback("add time"))),
        .plain(" "),
        .textButton(syntheticButton("cancel", kind: .regular, action: syntheticCallback("cancel")))
    ])

    return InstantPage(
        blocks: [
            .paragraph(firstParagraph),
            .paragraph(secondParagraph),
            .buttonRow(alignment: .justify, buttons: [
                syntheticButton("Start", kind: .accent, action: syntheticCallback("Start")),
                syntheticButton("Skip", kind: .regular, action: syntheticCallback("Skip")),
                syntheticButton("Share", kind: .regular, action: .disabled)
            ]),
            .paragraph(invitationParagraph),
            .buttonRow(alignment: .left, buttons: [
                syntheticButton("Accept", kind: .success, action: .disabled),
                syntheticButton("Decline", kind: .destructive, action: .disabled)
            ]),
            .buttonRow(alignment: .center, buttons: [
                syntheticButton("Accept", kind: .success, action: syntheticCallback("Accept")),
                syntheticButton("Decline", kind: .destructive, action: syntheticCallback("Decline"))
            ]),
            .paragraph(estimateParagraph),
            .buttonRow(alignment: .right, buttons: [
                // Deliberately NOT a telegram.org URL: `execute(inapp:)` drops the confirmation when the
                // host is in the server's `whitelisted_domains` app-config, so a Telegram link opens
                // silently and the confirm path never gets exercised.
                syntheticButton("Open", kind: .accent, action: .url("https://example.com")),
                syntheticButton("Share", kind: .regular, action: .switchInline(samePeer: false, query: "", peerTypes: []))
            ]),
            .buttonRow(alignment: .left, buttons: [
                syntheticButton("Copy", kind: .regular, action: .copyText(payload: "Copy")),
                syntheticButton("Profile", kind: .regular, action: .openUserProfile(peerId: peerId))
            ]),
            .buttonRow(alignment: .center, buttons: [
                syntheticButton("Open", kind: .accent, action: .url("https://telegram.org"), isEnabled: false),
                syntheticButton("Profile", kind: .regular, action: .openUserProfile(peerId: peerId), isEnabled: false)
            ]),
            .buttonRow(alignment: .right, buttons: [
                syntheticButton("Open App", kind: .accent, action: .openWebApp)
            ]),
            .paragraph(.plain("Thank you!"))
        ],
        media: [:],
        isComplete: true,
        rtl: false,
        url: "",
        views: nil
    )
}

/// True when `text` is exactly the synthetic-buttons command.
public func isChatSyntheticButtonsCommand(_ text: String) -> Bool {
    return text.trimmingCharacters(in: .whitespacesAndNewlines) == chatSyntheticButtonsCommand
}

/// Inserts the fixture as a pair of local messages (one incoming, one outgoing). Nothing is sent to
/// the server.
public func insertSyntheticButtonsMessages(context: any AccountContextProtocol, peerId: PeerId, threadId: Int64?) {
    let page = syntheticButtonsInstantPage(peerId: peerId)
    // `text` is left empty, so the message renders purely from its RichTextMessageAttribute; the
    // chat-list preview shows nothing for it, which is acceptable for a debug fixture.
    let timestamp = Int32(Date().timeIntervalSince1970)
    let accountPeerId = context.account.peerId

    func store(incoming: Bool) -> StoreMessage {
        return StoreMessage(
            peerId: peerId,
            namespace: Namespaces.Message.Local,
            customStableId: nil,
            globallyUniqueId: nil,
            groupingKey: nil,
            threadId: threadId,
            timestamp: incoming ? timestamp : timestamp + 1,
            flags: incoming ? [.Incoming] : [],
            tags: [],
            globalTags: [],
            localTags: [],
            forwardInfo: nil,
            authorId: incoming ? peerId : accountPeerId,
            text: "",
            attributes: [RichTextMessageAttribute(instantPage: page, fullInstantPage: nil)],
            media: []
        )
    }

    _ = (context.account.postbox.transaction { transaction -> Void in
        _ = transaction.addMessages([store(incoming: true)], location: .UpperHistoryBlock)
        _ = transaction.addMessages([store(incoming: false)], location: .UpperHistoryBlock)
    }).start()
}

#endif
