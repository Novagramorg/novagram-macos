import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramContext
import TelegramTheme
import GeneralRows
import AvatarUI
import Localization
import NovagramCore

func novagramJobPeerTitle(_ peer: Peer?) -> String {
    if let channel = peer as? TelegramChannel {
        return channel.title
    }
    if let group = peer as? TelegramGroup {
        return group.title
    }
    if let user = peer as? TelegramUser {
        return [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }
    return ""
}

func novagramJobContactText(_ contact: NovagramJobContact) -> String {
    switch contact {
    case let .username(value):
        return value.hasPrefix("@") ? value : "@" + value
    case let .phone(value), let .email(value), let .link(value):
        return value
    }
}

func novagramJobFormatTitle(_ format: NovagramJobWorkFormat) -> String {
    let strings = NovagramL10n.current
    switch format {
    case .office:
        return strings.jobSearch_formatOffice
    case .remote:
        return strings.jobSearch_formatRemote
    case .hybrid:
        return strings.jobSearch_formatHybrid
    }
}

func novagramJobChips(_ info: NovagramJobPostInfo) -> [String] {
    let strings = NovagramL10n.current
    let language = appCurrentLanguage.languageCode
    var chips: [String] = []
    if let salary = info.salary {
        chips.append(salary.isNegotiable && salary.text.isEmpty ? strings.jobSearch_negotiable : salary.text)
    }
    chips += info.cityIds.compactMap { NovagramJobPresets.city(id: $0)?.title(languageCode: language) }
    chips += NovagramJobWorkFormat.allCases.filter { info.formats.contains($0) }.map(novagramJobFormatTitle)
    if let years = info.experienceYears {
        chips.append(strings.jobSearch_experience(years))
    }
    return chips.filter { !$0.isEmpty }
}

func novagramJobSnippet(_ result: NovagramJobResult) -> String {
    let maxSalaryLabelLetters = 12
    var lines = result.text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
    let title = result.info.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let titleIndex = title.isEmpty ? nil : lines.firstIndex(where: { $0.range(of: title, options: [.caseInsensitive, .diacriticInsensitive]) != nil })
    if let titleIndex {
        lines.removeFirst(titleIndex + 1)
    } else if let firstIndex = lines.firstIndex(where: { !$0.isEmpty }) {
        lines.removeFirst(firstIndex + 1)
    }
    let salary = result.info.salary?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !salary.isEmpty {
        lines.removeAll { line in
            guard let range = line.range(of: salary, options: [.caseInsensitive]) else {
                return false
            }
            var rest = line
            rest.removeSubrange(range)
            return rest.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count <= maxSalaryLabelLetters
        }
    }
    let kept = lines.filter { !$0.isEmpty }
    return kept.joined(separator: "\n")
}

final class NovagramJobResultRowItem: GeneralRowItem {
    fileprivate static let padding: CGFloat = 12
    fileprivate static let avatarSize: CGFloat = 36
    fileprivate static let buttonsHeight: CGFloat = 28
    fileprivate static let spacing: CGFloat = 6
    private static let snippetLines: Int32 = 3

    let context: any AccountContextProtocol
    let result: NovagramJobResult
    let peer: Peer?
    let headerLayout: TextViewLayout
    let titleLayout: TextViewLayout
    let chipsLayout: TextViewLayout?
    let snippetLayout: TextViewLayout
    let canWrite: Bool
    let writeTitle: String
    let contact: String?
    let openPost: () -> Void
    let write: () -> Void
    let copyContact: () -> Void

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, result: NovagramJobResult, viewType: GeneralViewType, openPost: @escaping () -> Void, write: @escaping () -> Void, copyContact: @escaping () -> Void) {
        self.context = context
        self.result = result
        self.openPost = openPost
        self.write = write
        self.copyContact = copyContact
        let message = result.message
        self.peer = message.peers[message.id.peerId]
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let date = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp)))
        let header = NSMutableAttributedString()
        header.append(NSAttributedString(string: novagramJobPeerTitle(self.peer), attributes: [.font: NSFont.medium(.text), .foregroundColor: theme.colors.text]))
        header.append(NSAttributedString(string: "\n" + date, attributes: [.font: NSFont.normal(.small), .foregroundColor: theme.colors.grayText]))
        self.headerLayout = TextViewLayout(header, maximumNumberOfLines: 2)
        let firstLine = result.text.split(separator: "\n").first.map(String.init) ?? result.text
        let title = (result.info.title?.isEmpty == false ? result.info.title : nil) ?? firstLine
        self.titleLayout = TextViewLayout(NSAttributedString(string: title, attributes: [.font: NSFont.medium(.title), .foregroundColor: theme.colors.text]), maximumNumberOfLines: 2)
        let chips = novagramJobChips(result.info)
        self.chipsLayout = chips.isEmpty ? nil : TextViewLayout(NSAttributedString(string: chips.joined(separator: "  •  "), attributes: [.font: NSFont.medium(.short), .foregroundColor: theme.colors.accent]), maximumNumberOfLines: 2)
        self.snippetLayout = TextViewLayout(NSAttributedString(string: novagramJobSnippet(result), attributes: [.font: NSFont.normal(.text), .foregroundColor: theme.colors.grayText]), maximumNumberOfLines: NovagramJobResultRowItem.snippetLines)
        let hasUsername = result.info.contacts.contains { if case .username = $0 { return true } else { return false } }
        self.canWrite = hasUsername || message.author is TelegramUser
        let firstUsername = result.info.contacts.compactMap { contact -> NovagramJobContact? in
            if case .username = contact {
                return contact
            }
            return nil
        }.first
        self.writeTitle = firstUsername.map { NovagramL10n.current.jobSearch_writeTo(novagramJobContactText($0)) } ?? NovagramL10n.current.jobSearch_write
        self.contact = result.info.contacts.first.map(novagramJobContactText)
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    var contentWidth: CGFloat {
        return blockWidth - NovagramJobResultRowItem.padding * 2
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        headerLayout.measure(width: contentWidth - NovagramJobResultRowItem.avatarSize - 10)
        titleLayout.measure(width: contentWidth)
        chipsLayout?.measure(width: contentWidth)
        snippetLayout.measure(width: contentWidth)
        return true
    }

    override var height: CGFloat {
        let padding = NovagramJobResultRowItem.padding
        let spacing = NovagramJobResultRowItem.spacing
        var total = padding + max(NovagramJobResultRowItem.avatarSize, headerLayout.layoutSize.height) + spacing
        total += titleLayout.layoutSize.height + spacing
        if let chipsLayout {
            total += chipsLayout.layoutSize.height + spacing
        }
        total += snippetLayout.layoutSize.height + spacing
        total += NovagramJobResultRowItem.buttonsHeight + padding
        return total
    }

    override func viewClass() -> AnyClass {
        return NovagramJobResultRowView.self
    }
}

private final class NovagramJobResultRowView: GeneralContainableRowView {
    private let avatar = AvatarControl(font: .avatar(13))
    private let headerView = TextView()
    private let titleView = TextView()
    private let chipsView = TextView()
    private let snippetView = TextView()
    private let openButton = TextButton()
    private let writeButton = TextButton()
    private let copyButton = TextButton()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatar.setFrameSize(NSSize(width: NovagramJobResultRowItem.avatarSize, height: NovagramJobResultRowItem.avatarSize))
        for view in [headerView, titleView, chipsView, snippetView] {
            view.userInteractionEnabled = false
            view.isSelectable = false
            containerView.addSubview(view)
        }
        containerView.addSubview(avatar)
        for button in [openButton, writeButton, copyButton] {
            button.set(font: .medium(.text), for: .Normal)
            button.scaleOnClick = true
            containerView.addSubview(button)
        }
        openButton.set(handler: { [weak self] _ in
            (self?.item as? NovagramJobResultRowItem)?.openPost()
        }, for: .Click)
        writeButton.set(handler: { [weak self] _ in
            (self?.item as? NovagramJobResultRowItem)?.write()
        }, for: .Click)
        copyButton.set(handler: { [weak self] _ in
            (self?.item as? NovagramJobResultRowItem)?.copyContact()
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? NovagramJobResultRowItem else {
            return
        }
        let strings = NovagramL10n.current
        avatar.setPeer(account: item.context.account, peer: item.peer)
        headerView.update(item.headerLayout)
        titleView.update(item.titleLayout)
        chipsView.update(item.chipsLayout)
        chipsView.isHidden = item.chipsLayout == nil
        snippetView.update(item.snippetLayout)
        openButton.set(text: strings.jobSearch_openPost, for: .Normal)
        writeButton.set(text: item.writeTitle, for: .Normal)
        copyButton.set(text: strings.jobSearch_copyContact, for: .Normal)
        for button in [openButton, writeButton, copyButton] {
            button.set(color: theme.colors.accent, for: .Normal)
            button.sizeToFit()
        }
        writeButton.isHidden = !item.canWrite
        copyButton.isHidden = item.contact == nil
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? NovagramJobResultRowItem else {
            return
        }
        let padding = NovagramJobResultRowItem.padding
        let spacing = NovagramJobResultRowItem.spacing
        avatar.setFrameOrigin(NSPoint(x: padding, y: padding))
        let headerHeight = max(NovagramJobResultRowItem.avatarSize, item.headerLayout.layoutSize.height)
        headerView.setFrameOrigin(NSPoint(x: avatar.frame.maxX + 10, y: padding + floor((headerHeight - item.headerLayout.layoutSize.height) / 2)))
        var y = padding + headerHeight + spacing
        titleView.setFrameOrigin(NSPoint(x: padding, y: y))
        y += item.titleLayout.layoutSize.height + spacing
        if let chipsLayout = item.chipsLayout {
            chipsView.setFrameOrigin(NSPoint(x: padding, y: y))
            y += chipsLayout.layoutSize.height + spacing
        }
        snippetView.setFrameOrigin(NSPoint(x: padding, y: y))
        y += item.snippetLayout.layoutSize.height + spacing
        var x = padding
        for button in [openButton, writeButton, copyButton] where !button.isHidden {
            button.setFrameOrigin(NSPoint(x: x, y: y + floor((NovagramJobResultRowItem.buttonsHeight - button.frame.height) / 2)))
            x = button.frame.maxX + 16
        }
    }
}
