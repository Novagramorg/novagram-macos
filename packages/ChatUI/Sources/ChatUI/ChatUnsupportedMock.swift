import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
#if SHARE
import TelegramThemeShare
import TelegramContextShare
#else
import TelegramTheme
import TelegramContext
#endif

#if DEBUG

public let chatUnsupportedMessageCommand = "/unsupported_message"
public let chatUnsupportedMessage2Command = "/unsupported_message2"

/// True when `text` is exactly the unsupported-message command.
public func isChatUnsupportedMessageCommand(_ text: String) -> Bool {
    return text.trimmingCharacters(in: .whitespacesAndNewlines) == chatUnsupportedMessageCommand
}

/// True when `text` is exactly the resolved-file rich-message command.
public func isChatUnsupportedMessage2Command(_ text: String) -> Bool {
    return text.trimmingCharacters(in: .whitespacesAndNewlines) == chatUnsupportedMessage2Command
}

private func unsupportedBlockInstantPage() -> InstantPage {
    let missingDocumentId = MediaId(namespace: Namespaces.Media.CloudFile, id: Int64.max - 1)
    return InstantPage(
        blocks: [
            .header(.plain("Artemis II Crew")),
            .paragraph(.concat([
                .bold(.plain("Artemis II")),
                .plain(" will carry a crew of four astronauts representing "),
                .bold(.plain("NASA")),
                .plain(" and its international partners.")
            ])),
            .subheader(.plain("Crew Highlights")),
            .unsupported,
            .paragraph(.plain("The next attachment deliberately has no matching document.")),
            .document(
                id: missingDocumentId,
                caption: InstantPageCaption(
                    text: .plain("This caption must remain visible below the unsupported band."),
                    credit: .empty
                )
            ),
            .list(items: [
                .text(.plain("4 astronauts on board"), nil, nil),
                .text(.concat([
                    .plain("Includes "),
                    .url(text: .plain("NASA"), url: "https://t.me/telegram", webpageId: nil),
                    .plain(" and "),
                    .url(text: .plain("CSA"), url: "https://t.me/telegram", webpageId: nil),
                    .plain(" members")
                ]), nil, nil),
                .text(.plain("First woman and first person of color"), nil, nil)
            ], ordered: false),
            .paragraph(.plain("Crew roles and assignments are subject to mission requirements."))
        ],
        media: [:],
        isComplete: true,
        rtl: false,
        url: "",
        views: nil
    )
}

/// Inserts exactly two incoming local messages: the Artemis rich-message sample and one whole-message
/// unsupported card. Nothing is sent to the server.
public func insertUnsupportedMockMessages(context: any AccountContextProtocol, peerId: PeerId, threadId: Int64?) {
    let timestamp = Int32(Date().timeIntervalSince1970)

    func store(rich: Bool, offset: Int32) -> StoreMessage {
        return StoreMessage(
            peerId: peerId,
            namespace: Namespaces.Message.Local,
            customStableId: nil,
            globallyUniqueId: nil,
            groupingKey: nil,
            threadId: threadId,
            timestamp: timestamp + offset,
            flags: [.Incoming],
            tags: [],
            globalTags: [],
            localTags: [],
            forwardInfo: nil,
            authorId: peerId,
            text: "",
            attributes: rich ? [RichTextMessageAttribute(instantPage: unsupportedBlockInstantPage(), fullInstantPage: nil)] : [],
            media: rich ? [] : [TelegramMediaUnsupported()]
        )
    }

    _ = (context.account.postbox.transaction { transaction -> Void in
        _ = transaction.addMessages([
            store(rich: true, offset: 0),
            store(rich: false, offset: 1)
        ], location: .UpperHistoryBlock)
    }).start()
}

/// Inserts one incoming local rich message whose document resolves through `InstantPage.media`.
/// The bytes are already in MediaBox, so the row starts in the fully available state.
public func insertSupportedFileMockMessage(context: any AccountContextProtocol, peerId: PeerId, threadId: Int64?) {
    let data = Data("This file is stored locally for the resolved rich-message document fixture.\n".utf8)
    let localId = Int64.random(in: Int64.min ... Int64.max)
    let resource = LocalFileMediaResource(fileId: localId, size: Int64(data.count))
    let mediaId = MediaId(namespace: Namespaces.Media.LocalFile, id: localId)
    let file = TelegramMediaFile(
        fileId: mediaId,
        partialReference: nil,
        resource: resource,
        previewRepresentations: [],
        videoThumbnails: [],
        immediateThumbnailData: nil,
        mimeType: "text/plain",
        size: Int64(data.count),
        attributes: [.FileName(fileName: "rich-message-sample.txt")],
        alternativeRepresentations: []
    )
    let instantPage = InstantPage(
        blocks: [
            .paragraph(.plain("Below this text is a resolved file.")),
            .document(
                id: mediaId,
                caption: InstantPageCaption(
                    text: .plain("This file resolves from InstantPage.media and renders normally."),
                    credit: .empty
                )
            ),
            .paragraph(.plain("Above this text is the resolved file."))
        ],
        media: [mediaId: EngineMedia(file)],
        isComplete: true,
        rtl: false,
        url: "",
        views: nil
    )

    context.account.postbox.mediaBox.storeResourceData(resource.id, data: data, synchronous: true)

    let message = StoreMessage(
        peerId: peerId,
        namespace: Namespaces.Message.Local,
        customStableId: nil,
        globallyUniqueId: nil,
        groupingKey: nil,
        threadId: threadId,
        timestamp: Int32(Date().timeIntervalSince1970),
        flags: [.Incoming],
        tags: [],
        globalTags: [],
        localTags: [],
        forwardInfo: nil,
        authorId: peerId,
        text: "",
        attributes: [RichTextMessageAttribute(instantPage: instantPage, fullInstantPage: nil)],
        media: []
    )

    _ = (context.account.postbox.transaction { transaction -> Void in
        _ = transaction.addMessages([message], location: .UpperHistoryBlock)
    }).start()
}

#endif
