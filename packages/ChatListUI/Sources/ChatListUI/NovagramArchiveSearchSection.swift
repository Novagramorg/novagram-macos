import Cocoa
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramContext
import TelegramTheme
import TelegramUtils
import AvatarUI
import AlertsUI
import NovagramCore

private let novagramArchiveSeparatorIndex = 17000
private let novagramArchiveRowHeight: CGFloat = 56
private let novagramArchiveMoreRowHeight: CGFloat = 36
private let novagramArchiveTextInset: CGFloat = 56
private let novagramArchiveAvatarSize: CGFloat = 36
private let novagramArchiveAvatarInset: CGFloat = 10
private let novagramArchiveSideInset: CGFloat = 10
private let novagramArchiveBadgeGap: CGFloat = 6
private let novagramArchiveBadgePadding = NSSize(width: 4, height: 1)
private let novagramArchiveSnippetLead = 24

struct NovagramArchiveSearchRecord: Equatable {
    let hit: NovagramArchiveHit
    let peer: Peer
    let query: String

    static func == (lhs: NovagramArchiveSearchRecord, rhs: NovagramArchiveSearchRecord) -> Bool {
        return lhs.hit == rhs.hit && lhs.peer.isEqual(rhs.peer) && lhs.query == rhs.query
    }
}

enum NovagramArchiveSearchItem: Equatable {
    case record(NovagramArchiveSearchRecord)
    case more(NovagramArchiveSearchSession)

    var stableKey: String {
        switch self {
        case let .record(record):
            return record.hit.key
        case .more:
            return "more"
        }
    }

    static func == (lhs: NovagramArchiveSearchItem, rhs: NovagramArchiveSearchItem) -> Bool {
        switch (lhs, rhs) {
        case let (.record(lhsRecord), .record(rhsRecord)):
            return lhsRecord == rhsRecord
        case let (.more(lhsSession), .more(rhsSession)):
            return lhsSession === rhsSession
        default:
            return false
        }
    }
}

struct NovagramArchiveSearchSectionData {
    let records: [NovagramArchiveSearchRecord]
    let session: NovagramArchiveSearchSession?

    static let empty = NovagramArchiveSearchSectionData(records: [], session: nil)
}

func novagramArchiveSearch(
    _ context: any AccountContextProtocol,
    query: String,
    target: SearchControllerTarget,
    tags: SearchTags,
    options: AppSearchOptions
) -> Signal<NovagramArchiveSearchSectionData, NoError> {
    guard target.isCommon, options.contains(.messages), tags.isEmpty, !query.hasPrefix("#"), !query.hasPrefix("$") else {
        return .single(.empty)
    }
    let postbox = context.account.postbox
    return NovagramMessageArchive.shared.search(accountRecordId: context.account.id.int64, query: query)
        |> mapToSignal { results -> Signal<NovagramArchiveSearchSectionData, NoError> in
            guard !results.hits.isEmpty else {
                return .single(.empty)
            }
            return postbox.transaction { transaction -> NovagramArchiveSearchSectionData in
                var seen = Set<String>()
                var records: [NovagramArchiveSearchRecord] = []
                for hit in results.hits {
                    guard seen.insert(hit.key).inserted, let peer = transaction.getPeer(hit.chatPeerId) else {
                        continue
                    }
                    records.append(NovagramArchiveSearchRecord(hit: hit, peer: peer, query: results.query))
                }
                return NovagramArchiveSearchSectionData(records: records, session: results.session)
            }
        }
}

func novagramArchiveSearchEntries<Entry>(
    _ data: NovagramArchiveSearchSectionData,
    separator: (String, Int) -> Entry,
    row: (NovagramArchiveSearchItem, Int) -> Entry
) -> [Entry] {
    guard !data.records.isEmpty else {
        return []
    }
    let start = novagramArchiveSeparatorIndex
    var entries = [separator(NovagramL10n.current.search_archiveSection, start)]
    entries += data.records.enumerated().map { row(.record($0.element), start + 1 + $0.offset) }
    if let session = data.session {
        entries.append(row(.more(session), start + 1 + data.records.count))
    }
    return entries
}

func novagramArchiveSearchRow(
    _ initialSize: NSSize,
    item: NovagramArchiveSearchItem,
    context: any AccountContextProtocol,
    stableId: AnyHashable
) -> TableRowItem {
    switch item {
    case let .record(record):
        return NovagramArchiveSearchRowItem(initialSize, stableId: stableId, context: context, record: record)
    case let .more(session):
        return NovagramArchiveSearchMoreRowItem(initialSize, stableId: stableId, session: session)
    }
}

func novagramIsArchiveSearchRow(_ item: TableRowItem) -> Bool {
    return item is NovagramArchiveSearchRowItem || item is NovagramArchiveSearchMoreRowItem
}

func novagramOpenArchiveSearchRow(_ item: TableRowItem, context: any AccountContextProtocol) -> Bool {
    if let item = item as? NovagramArchiveSearchMoreRowItem {
        item.session.loadMore()
        return true
    }
    guard let item = item as? NovagramArchiveSearchRowItem else {
        return false
    }
    if item.record.hit.isDeleted {
        novagramPresentDeletedArchiveRecord(item.record, context: context)
    } else {
        novagramPresentEditedArchiveRecord(item.record, context: context)
    }
    return true
}

private func novagramPresentEditedArchiveRecord(_ record: NovagramArchiveSearchRecord, context: any AccountContextProtocol) {
    let hit = record.hit
    let messageId = MessageId(peerId: hit.chatPeerId, namespace: Namespaces.Message.Cloud, id: hit.messageId)
    _ = (context.account.postbox.transaction { transaction -> String in
        return transaction.getMessage(messageId)?.text ?? ""
    } |> deliverOnMainQueue).start(next: { currentText in
        NovagramHooks.shared.presentEditedHistory(context, hit.chatPeerId, hit.messageId, currentText)
    })
}

private func novagramPresentDeletedArchiveRecord(_ record: NovagramArchiveSearchRecord, context: any AccountContextProtocol) {
    let l10n = NovagramL10n.current
    let date = novagramArchiveDateString(record.hit.eventDate, full: true)
    let information = l10n.search_archiveDeletedAt(date) + "\n\n" + record.hit.text
    let peerId = record.hit.chatPeerId
    verifyAlert(for: context.window, header: record.peer.displayTitle, information: information, ok: l10n.search_archiveOpenChat, cancel: l10n.search_archiveClose, successHandler: { _ in
        NovagramHooks.shared.openChat(context, peerId)
    })
}

private func novagramArchiveDateString(_ timestamp: Int32, full: Bool) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    let formatter = DateFormatter()
    if full {
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
    } else if Calendar.current.isDateInToday(date) {
        formatter.dateStyle = .none
        formatter.timeStyle = .short
    } else {
        formatter.dateStyle = .short
        formatter.timeStyle = .none
    }
    return formatter.string(from: date)
}

private func novagramArchiveSearchTerm(_ query: String) -> String? {
    let skipped = CharacterSet(charactersIn: "\"«»#")
    let terms = query.split(separator: " ").map { String($0).trimmingCharacters(in: skipped) }
    return terms.first(where: { !$0.isEmpty && !$0.hasPrefix("-") })
}

private func novagramArchiveSnippet(_ text: String, query: String) -> NSAttributedString {
    let flat = text.replacingOccurrences(of: "\n", with: " ")
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    var snippet = flat
    if let term = novagramArchiveSearchTerm(query), let range = flat.range(of: term, options: options) {
        let start = flat.index(range.lowerBound, offsetBy: -novagramArchiveSnippetLead, limitedBy: flat.startIndex) ?? flat.startIndex
        snippet = (start == flat.startIndex ? "" : "…") + String(flat[start...])
    }
    let result = NSMutableAttributedString(string: snippet, attributes: [.foregroundColor: theme.colors.grayText, .font: NSFont.normal(.text)])
    if let term = novagramArchiveSearchTerm(query), let range = snippet.range(of: term, options: options) {
        result.addAttributes([.foregroundColor: theme.colors.text, .font: NSFont.medium(.text)], range: NSRange(range, in: snippet))
    }
    return result
}

final class NovagramArchiveSearchRowItem: TableRowItem {
    private let _stableId: AnyHashable
    let context: any AccountContextProtocol
    let record: NovagramArchiveSearchRecord
    let titleLayout: TextViewLayout
    let dateLayout: TextViewLayout
    let badgeLayout: TextViewLayout
    let snippetLayout: TextViewLayout
    let badgeColor: NSColor

    override var stableId: AnyHashable {
        return _stableId
    }

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, record: NovagramArchiveSearchRecord) {
        self._stableId = stableId
        self.context = context
        self.record = record
        let l10n = NovagramL10n.current
        self.badgeColor = record.hit.isDeleted ? theme.colors.redUI : theme.colors.accent
        self.titleLayout = TextViewLayout(.initialize(string: record.peer.displayTitle, color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1)
        self.dateLayout = TextViewLayout(.initialize(string: novagramArchiveDateString(record.hit.eventDate, full: false), color: theme.colors.grayText, font: .normal(.short)), maximumNumberOfLines: 1)
        self.badgeLayout = TextViewLayout(.initialize(string: record.hit.isDeleted ? l10n.search_archiveDeleted : l10n.search_archiveEdited, color: badgeColor, font: .medium(.small)), maximumNumberOfLines: 1)
        self.snippetLayout = TextViewLayout(novagramArchiveSnippet(record.hit.text, query: record.query), maximumNumberOfLines: 1)
        super.init(initialSize)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        dateLayout.measure(width: .greatestFiniteMagnitude)
        badgeLayout.measure(width: .greatestFiniteMagnitude)
        titleLayout.measure(width: max(0, width - novagramArchiveTextInset - dateLayout.layoutSize.width - novagramArchiveSideInset * 2))
        let badgeWidth = badgeLayout.layoutSize.width + novagramArchiveBadgePadding.width * 2 + novagramArchiveBadgeGap
        snippetLayout.measure(width: max(0, width - novagramArchiveTextInset - badgeWidth - novagramArchiveSideInset))
        return success
    }

    override var height: CGFloat {
        return novagramArchiveRowHeight
    }

    override func viewClass() -> AnyClass {
        return NovagramArchiveSearchRowView.self
    }

    override var accessibilityLabel: String? {
        return [titleLayout.attributedString.string, badgeLayout.attributedString.string, dateLayout.attributedString.string, record.hit.text].joined(separator: ", ")
    }
}

final class NovagramArchiveSearchRowView: TableRowView {
    private let avatar = AvatarControl(font: .avatar(.text))
    private let titleView = TextView()
    private let dateView = TextView()
    private let badgeView = View()
    private let badgeTextView = TextView()
    private let snippetView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatar.setFrameSize(NSSize(width: novagramArchiveAvatarSize, height: novagramArchiveAvatarSize))
        avatar.userInteractionEnabled = false
        for textView in [titleView, dateView, badgeTextView, snippetView] {
            textView.userInteractionEnabled = false
            textView.isSelectable = false
        }
        badgeView.layer?.cornerRadius = 4
        badgeView.addSubview(badgeTextView)
        addSubview(avatar)
        addSubview(titleView)
        addSubview(dateView)
        addSubview(badgeView)
        addSubview(snippetView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return theme.colors.background
    }

    override func updateColors() {
        super.updateColors()
        for textView in [titleView, dateView, snippetView] {
            textView.backgroundColor = backdorColor
        }
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? NovagramArchiveSearchRowItem else {
            return
        }
        avatar.setPeer(account: item.context.account, peer: item.record.peer)
        titleView.update(item.titleLayout)
        dateView.update(item.dateLayout)
        badgeTextView.update(item.badgeLayout)
        snippetView.update(item.snippetLayout)
        badgeView.backgroundColor = item.badgeColor.withAlphaComponent(0.15)
        needsLayout = true
    }

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        ctx.setFillColor(theme.colors.border.cgColor)
        ctx.fill(NSRect(x: novagramArchiveTextInset, y: frame.height - .borderSize, width: frame.width - novagramArchiveTextInset, height: .borderSize))
        ctx.fill(NSRect(x: frame.width - .borderSize, y: 0, width: .borderSize, height: frame.height))
    }

    override func layout() {
        super.layout()
        avatar.centerY(x: novagramArchiveAvatarInset)
        let top: CGFloat = 8
        titleView.setFrameOrigin(NSPoint(x: novagramArchiveTextInset, y: top))
        dateView.setFrameOrigin(NSPoint(x: frame.width - dateView.frame.width - novagramArchiveSideInset, y: top + 1))
        badgeView.setFrameSize(NSSize(width: badgeTextView.frame.width + novagramArchiveBadgePadding.width * 2, height: badgeTextView.frame.height + novagramArchiveBadgePadding.height * 2))
        badgeTextView.setFrameOrigin(NSPoint(x: novagramArchiveBadgePadding.width, y: novagramArchiveBadgePadding.height))
        let secondLineY = frame.height - top - max(badgeView.frame.height, snippetView.frame.height)
        badgeView.setFrameOrigin(NSPoint(x: novagramArchiveTextInset, y: secondLineY + (snippetView.frame.height - badgeView.frame.height) / 2))
        snippetView.setFrameOrigin(NSPoint(x: badgeView.frame.maxX + novagramArchiveBadgeGap, y: secondLineY))
    }
}

final class NovagramArchiveSearchMoreRowItem: TableRowItem {
    private let _stableId: AnyHashable
    let session: NovagramArchiveSearchSession
    let textLayout: TextViewLayout

    override var stableId: AnyHashable {
        return _stableId
    }

    init(_ initialSize: NSSize, stableId: AnyHashable, session: NovagramArchiveSearchSession) {
        self._stableId = stableId
        self.session = session
        self.textLayout = TextViewLayout(.initialize(string: NovagramL10n.current.search_archiveShowMore, color: theme.colors.accent, font: .normal(.text)), maximumNumberOfLines: 1)
        super.init(initialSize)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        textLayout.measure(width: max(0, width - novagramArchiveTextInset - novagramArchiveSideInset))
        return success
    }

    override var height: CGFloat {
        return novagramArchiveMoreRowHeight
    }

    override func viewClass() -> AnyClass {
        return NovagramArchiveSearchMoreRowView.self
    }

    override var accessibilityLabel: String? {
        return textLayout.attributedString.string
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }
}

final class NovagramArchiveSearchMoreRowView: TableRowView {
    private let textView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        addSubview(textView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return theme.colors.background
    }

    override func updateColors() {
        super.updateColors()
        textView.backgroundColor = backdorColor
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? NovagramArchiveSearchMoreRowItem else {
            return
        }
        textView.update(item.textLayout)
        needsLayout = true
    }

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        ctx.setFillColor(theme.colors.border.cgColor)
        ctx.fill(NSRect(x: frame.width - .borderSize, y: 0, width: .borderSize, height: frame.height))
    }

    override func layout() {
        super.layout()
        textView.centerY(x: novagramArchiveTextInset)
    }
}
