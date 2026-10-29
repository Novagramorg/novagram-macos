//
//  NovagramEditedHistoryController.swift
//  Telegram-Mac
//
//  Viewer for the Novagram-local edited-message history (stored by
//  NovagramEditedHistoryManager): the current version first, then the earlier
//  versions newest first. Each version shows its time, its text and its media
//  (photo or video thumbnail, a line for other files), like iOS.

import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import GeneralRows
import TelegramMediaUtils
import NovagramCore

// MARK: - Version row

private struct EHVersion: Equatable {
    let title: String
    let text: String
    let media: [Media]

    static func == (lhs: EHVersion, rhs: EHVersion) -> Bool {
        return lhs.title == rhs.title && lhs.text == rhs.text && lhs.media.map { $0.id } == rhs.media.map { $0.id }
    }
}

private final class NovagramEditedHistoryRowItem: GeneralRowItem {
    static let maxMediaSize = NSMakeSize(280, 220)

    let context: AccountContext
    let peerId: PeerId
    let image: TelegramMediaImage?
    let video: TelegramMediaFile?
    let mediaSize: NSSize?
    private(set) var titleLayout: TextViewLayout
    private(set) var textLayout: TextViewLayout?

    init(_ initialSize: NSSize, stableId: AnyHashable, context: AccountContext, peerId: PeerId, version: EHVersion, viewType: GeneralViewType) {
        self.context = context
        self.peerId = peerId
        let l10n = NovagramL10n.current

        var image: TelegramMediaImage?
        var video: TelegramMediaFile?
        var mediaLine: String?
        for media in version.media {
            if let photo = media as? TelegramMediaImage {
                image = photo
            } else if let file = media as? TelegramMediaFile {
                if file.isVideo {
                    video = file
                } else {
                    mediaLine = "📎 " + l10n.editedHistory_file + (file.fileName.map { ": " + $0 } ?? "")
                }
            } else if mediaLine == nil {
                mediaLine = "📎 " + l10n.editedHistory_media
            }
        }
        self.image = image
        self.video = video

        let dimensions: NSSize?
        if let image, let representation = largestImageRepresentation(image.representations) {
            dimensions = representation.dimensions.size
        } else if let video {
            dimensions = video.dimensions?.size ?? NSMakeSize(320, 240)
        } else {
            dimensions = nil
        }
        self.mediaSize = dimensions.map { $0.aspectFitted(NovagramEditedHistoryRowItem.maxMediaSize) }

        self.titleLayout = TextViewLayout(.initialize(string: version.title, color: theme.colors.grayText, font: .normal(.short)))
        let body = [version.text, mediaLine].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        self.textLayout = body.isEmpty ? nil : TextViewLayout(.initialize(string: body, color: theme.colors.text, font: .normal(.text)))

        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        let textWidth = blockWidth - viewType.innerInset.left - viewType.innerInset.right
        titleLayout.measure(width: textWidth)
        textLayout?.measure(width: textWidth)
        return true
    }

    override var height: CGFloat {
        let inset = viewType.innerInset
        var height = inset.top + titleLayout.layoutSize.height
        if let textLayout {
            height += 4 + textLayout.layoutSize.height
        }
        if let mediaSize {
            height += 8 + mediaSize.height
        }
        return height + inset.bottom
    }

    override func viewClass() -> AnyClass {
        return NovagramEditedHistoryRowView.self
    }
}

private final class NovagramEditedHistoryRowView: GeneralContainableRowView {
    private let titleView = TextView()
    private let textView = TextView()
    private let mediaView = TransformImageView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        textView.isSelectable = true
        addSubview(titleView)
        addSubview(textView)
        addSubview(mediaView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        guard let item = item as? NovagramEditedHistoryRowItem else {
            return
        }
        let inset = item.viewType.innerInset
        titleView.setFrameOrigin(NSMakePoint(inset.left, inset.top))
        var y = titleView.frame.maxY
        if item.textLayout != nil {
            textView.setFrameOrigin(NSMakePoint(inset.left, y + 4))
            y = textView.frame.maxY
        }
        if let mediaSize = item.mediaSize {
            mediaView.frame = NSMakeRect(inset.left, y + 8, mediaSize.width, mediaSize.height)
        }
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? NovagramEditedHistoryRowItem else {
            return
        }
        titleView.update(item.titleLayout)
        textView.update(item.textLayout)
        textView.isHidden = item.textLayout == nil

        if let mediaSize = item.mediaSize {
            mediaView.isHidden = false
            if let image = item.image {
                mediaView.setSignal(chatMessagePhoto(account: item.context.account, imageReference: ImageMediaReference.standalone(media: image), scale: backingScaleFactor, autoFetchFullSize: true))
            } else if let video = item.video {
                mediaView.setSignal(chatMessageVideo(account: item.context.account, fileReference: FileMediaReference.standalone(media: video), scale: backingScaleFactor))
            }
            mediaView.set(arguments: TransformImageArguments(corners: ImageCorners(radius: 8), imageSize: mediaSize, boundingSize: mediaSize, intrinsicInsets: NSEdgeInsets()))
        } else {
            mediaView.isHidden = true
        }
        needsLayout = true
    }
}

// MARK: - Entries

private enum EHEntryId: Hashable {
    case section(Int)
    case header
    case version(Int)
    case footer
}

private enum EHEntry: Comparable, Identifiable {
    case section(Int)
    case header(Int, String)
    case version(Int, EHVersion)
    case footer(Int, String)

    var stableId: AnyHashable {
        switch self {
        case let .section(id): return EHEntryId.section(id)
        case .header: return EHEntryId.header
        case let .version(i, _): return EHEntryId.version(i)
        case .footer: return EHEntryId.footer
        }
    }

    var sortIndex: Int {
        switch self {
        case let .section(id): return id * 1000
        case let .header(i, _): return i
        case let .version(i, _): return i
        case let .footer(i, _): return i
        }
    }

    static func < (lhs: EHEntry, rhs: EHEntry) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }

    func item(initialSize: NSSize, context: AccountContext, peerId: PeerId) -> TableRowItem {
        switch self {
        case .section:
            return GeneralRowItem(initialSize, height: 16, stableId: stableId, viewType: .separator)
        case let .header(_, text):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: .textTopItem)
        case let .version(_, version):
            return NovagramEditedHistoryRowItem(initialSize, stableId: stableId, context: context, peerId: peerId, version: version, viewType: .singleItem)
        case let .footer(_, text):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: .textBottomItem)
        }
    }
}

private func editedHistoryEntries(current: EHVersion, history: [NovagramEditedHistoryEntry], l10n: NovagramL10n) -> [EHEntry] {
    var entries: [EHEntry] = []
    var idx = 0
    let next: () -> Int = { idx += 1; return idx }

    entries.append(.section(1))
    entries.append(.header(next(), l10n.editedHistory_listHeader))
    entries.append(.version(next(), current))

    for h in history.sorted(by: { $0.timestamp > $1.timestamp }) {
        entries.append(.section(idx + 1000))
        entries.append(.version(next(), EHVersion(title: stringForTimestamp(h.timestamp), text: h.text, media: h.media)))
    }

    entries.append(.section(99))
    entries.append(.footer(next(), history.isEmpty ? l10n.editedHistory_empty : l10n.editedHistory_footer))
    return entries
}

private func stringForTimestamp(_ ts: Int32) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(ts))
    let f = DateFormatter()
    f.dateStyle = .medium
    f.timeStyle = .short
    return f.string(from: date)
}

// MARK: - Controller

final class NovagramEditedHistoryController: TableViewController {

    private let peerId: PeerId
    private let messageId: Int32
    private let currentText: String
    private let disposable = MetaDisposable()

    override var defaultBarTitle: String {
        return NovagramL10n.current.editedHistory_screenTitle
    }

    override var removeAfterDisapper: Bool {
        return false
    }

    init(context: AccountContext, peerId: PeerId, messageId: Int32, currentText: String) {
        self.peerId = peerId
        self.messageId = messageId
        self.currentText = currentText
        super.init(context)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        disposable.dispose()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let context = self.context
        let peerId = self.peerId
        let currentText = self.currentText
        let initialSize = self.atomicSize
        let id = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: messageId)
        let history = NovagramEditedHistoryManager.shared.entries(peerId: peerId, messageId: messageId)
        let l10n = NovagramL10n.current

        // The current version comes from the message itself: its text, its media and its last edit time.
        disposable.set((context.engine.data.get(TelegramEngine.EngineData.Item.Messages.Message(id: id)) |> deliverOnMainQueue).start(next: { [weak self] message in
            let message = message?._asMessage()
            let date = message.map { ($0.attributes.compactMap { $0 as? EditedMessageAttribute }.first?.date) ?? $0.timestamp }
            let title = l10n.editedHistory_currentLabel + (date.map { ", " + stringForTimestamp($0) } ?? "")
            let media = message?.media.filter { !($0 is TelegramMediaWebpage) } ?? []
            let current = EHVersion(title: title, text: message?.text ?? currentText, media: media)
            let entries = editedHistoryEntries(current: current, history: history, l10n: l10n).map { AppearanceWrapperEntry(entry: $0, appearance: appAppearance) }
            let (removed, inserted, updated) = proccessEntriesWithoutReverse([], right: entries) { entry -> TableRowItem in
                return entry.entry.item(initialSize: initialSize.modify { $0 }, context: context, peerId: peerId)
            }
            self?.genericView.merge(with: TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: false))
            self?.readyOnce()
        }))
    }
}

// MARK: - Public helper

enum NovagramEditedHistory {
    /// Push the viewer onto the given navigation controller.
    static func push(navigation: NavigationViewController?,
                     context: AccountContext,
                     peerId: PeerId,
                     messageId: Int32,
                     currentText: String) {
        let controller = NovagramEditedHistoryController(context: context, peerId: peerId, messageId: messageId, currentText: currentText)
        navigation?.push(controller)
    }
}
