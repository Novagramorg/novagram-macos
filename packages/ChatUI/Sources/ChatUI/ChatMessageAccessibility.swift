import Foundation
import Postbox
import TelegramCore
import Localization

public struct ChatMessageAccessibility {
    public struct PollOption {
        public let text: String
        public let selected: Bool
        public let percent: Int?
    }

    public enum Kind {
        case text(String)
        case photo
        case video(duration: Int?)
        case voice(duration: Int?)
        case roundVideo(duration: Int?)
        case music(title: String?, performer: String?, duration: Int?)
        case file(name: String?, size: Int64?)
        case sticker(emoji: String?)
        case animatedSticker(emoji: String?)
        case contact(name: String, phones: [String], organization: String?)
        case poll(question: String, anonymous: Bool, options: [PollOption], votes: Int, closed: Bool)
        case linkPreview(text: String, title: String?, description: String?)
    }

    public enum Status {
        case none
        case sending
        case failed
        case sent(read: Bool, played: Bool?)
    }

    public struct Reply {
        public let authorName: String?
        public let isIncoming: Bool
        public let text: String
    }

    public enum Forward {
        case you
        case from(String)
    }

    public let kind: Kind
    public let isIncoming: Bool
    public let authorName: String?
    public let announceAuthor: Bool
    public let caption: String?
    public let date: String
    public let status: Status
    public let reply: Reply?
    public let forward: Forward?
    public let isSelected: Bool?
    public let pluralRecipients: Bool

    public init(kind: Kind, isIncoming: Bool, authorName: String?, announceAuthor: Bool, caption: String?, date: String, status: Status, reply: Reply? = nil, forward: Forward? = nil, isSelected: Bool? = nil, pluralRecipients: Bool = false) {
        self.kind = kind
        self.isIncoming = isIncoming
        self.authorName = authorName
        self.announceAuthor = announceAuthor
        self.caption = caption
        self.date = date
        self.status = status
        self.reply = reply
        self.forward = forward
        self.isSelected = isSelected
        self.pluralRecipients = pluralRecipients
    }

    private func pick(from: (String) -> String, plain: String, your: String) -> String {
        if !isIncoming {
            return your
        }
        if announceAuthor, let author = authorName, !author.isEmpty {
            return from(author)
        }
        return plain
    }

    private var kindLabel: String {
        switch kind {
        case .photo:
            return pick(from: strings().voiceOverChatPhotoFrom, plain: strings().voiceOverChatPhoto, your: strings().voiceOverChatYourPhoto)
        case .video:
            return pick(from: strings().voiceOverChatVideoFrom, plain: strings().voiceOverChatVideo, your: strings().voiceOverChatYourVideo)
        case .voice:
            return pick(from: strings().voiceOverChatVoiceMessageFrom, plain: strings().voiceOverChatVoiceMessage, your: strings().voiceOverChatYourVoiceMessage)
        case .roundVideo:
            return pick(from: strings().voiceOverChatVideoMessageFrom, plain: strings().voiceOverChatVideoMessage, your: strings().voiceOverChatYourVideoMessage)
        case .music:
            return pick(from: strings().voiceOverChatMusicFrom, plain: strings().voiceOverChatMusic, your: strings().voiceOverChatYourMusic)
        case .file:
            return pick(from: strings().voiceOverChatFileFrom, plain: strings().voiceOverChatFile, your: strings().voiceOverChatYourFile)
        case .sticker:
            return pick(from: strings().voiceOverChatStickerFrom, plain: strings().voiceOverChatSticker, your: strings().voiceOverChatYourSticker)
        case .animatedSticker:
            return pick(from: strings().voiceOverChatAnimatedStickerFrom, plain: strings().voiceOverChatAnimatedSticker, your: strings().voiceOverChatYourAnimatedSticker)
        case .contact:
            return pick(from: strings().voiceOverChatContactFrom, plain: strings().voiceOverChatContact, your: strings().voiceOverChatYourContact)
        case let .poll(_, anonymous, _, _, _):
            if anonymous {
                return pick(from: strings().voiceOverChatAnonymousPollFrom, plain: strings().voiceOverChatAnonymousPoll, your: strings().voiceOverChatYourAnonymousPoll)
            }
            return pick(from: strings().voiceOverChatPollFrom, plain: strings().voiceOverChatPoll, your: strings().voiceOverChatYourPoll)
        case .text, .linkPreview:
            if !isIncoming {
                return strings().voiceOverChatYourMessage
            }
            if let author = authorName, !author.isEmpty {
                return author
            }
            return strings().voiceOverChatMessage
        }
    }

    public var label: String {
        var label = kindLabel
        if let reply = reply {
            let prefix: String
            if reply.isIncoming, let author = reply.authorName, !author.isEmpty {
                prefix = strings().voiceOverChatReplyFrom(author)
            } else if reply.isIncoming {
                prefix = strings().voiceOverChatReply
            } else {
                prefix = strings().voiceOverChatReplyToYourMessage
            }
            label = prefix + ". " + label
        }
        if let forward = forward {
            switch forward {
            case .you:
                label = strings().voiceOverChatForwardedFromYou + ". " + label
            case let .from(name):
                label = strings().voiceOverChatForwardedFrom(name) + ". " + label
            }
        }
        return label
    }

    static func duration(_ seconds: Int?) -> String? {
        guard let seconds = seconds, seconds > 0 else {
            return nil
        }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .full
        return formatter.string(from: TimeInterval(seconds))
    }

    private var kindValue: String {
        var parts: [String] = []
        switch kind {
        case let .text(text):
            parts.append(text)
        case .photo:
            break
        case let .video(duration), let .voice(duration), let .roundVideo(duration):
            if let duration = ChatMessageAccessibility.duration(duration) {
                parts.append(strings().voiceOverChatDuration(duration))
            }
        case let .music(title, performer, duration):
            parts.append(strings().voiceOverChatMusicTitle(title ?? strings().voiceOverChatUnknown, performer ?? strings().voiceOverChatUnknown))
            if let duration = ChatMessageAccessibility.duration(duration) {
                parts.append(strings().voiceOverChatDuration(duration))
            }
        case let .file(name, size):
            if let name = name, !name.isEmpty {
                parts.append(name)
            }
            if let size = size, size > 0 {
                parts.append(strings().voiceOverChatSize(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))
            }
        case let .sticker(emoji), let .animatedSticker(emoji):
            if let emoji = emoji, !emoji.isEmpty {
                parts.append(emoji)
            }
        case let .contact(name, phones, organization):
            if !name.isEmpty {
                parts.append(name)
            }
            if phones.count == 1 {
                parts.append(strings().voiceOverChatContactPhoneNumber + ": " + phones[0])
            } else if phones.count > 1 {
                parts.append(strings().voiceOverChatContactPhoneNumberCountOther(phones.count) + ": " + phones.joined(separator: ", "))
            }
            if let organization = organization, !organization.isEmpty {
                parts.append(strings().voiceOverChatContactOrganization(organization))
            }
        case let .poll(question, _, options, votes, closed):
            parts.append(strings().voiceOverChatTitle(question))
            let optionText = options.map { option -> String in
                var text = option.text
                if option.selected {
                    text += ", " + strings().voiceOverChatOptionSelected
                }
                if let percent = option.percent {
                    text += ", \(percent)%"
                }
                return text
            }.joined(separator: ", ")
            parts.append(strings().voiceOverChatPollOptionCountOther(options.count) + ": " + optionText)
            parts.append(votes > 0 ? strings().voiceOverChatPollVotesOther(votes) : strings().voiceOverChatPollNoVotes)
            if closed {
                parts.append(strings().voiceOverChatPollFinalResults)
            }
        case let .linkPreview(text, title, description):
            if !text.isEmpty {
                parts.append(text)
            }
            var preview = strings().voiceOverChatPagePreview
            if let title = title, !title.isEmpty {
                preview += ". " + strings().voiceOverChatTitle(title)
            }
            if let description = description, !description.isEmpty {
                preview += ". " + description
            }
            parts.append(preview)
        }
        if let caption = caption, !caption.isEmpty {
            switch kind {
            case .text, .linkPreview, .poll, .contact:
                break
            default:
                parts.append(strings().voiceOverChatCaption(caption))
            }
        }
        return parts.joined(separator: ". ")
    }

    private var statusText: String? {
        guard !isIncoming else {
            return nil
        }
        switch status {
        case .none:
            return nil
        case .sending:
            return strings().voiceOverChatSending
        case .failed:
            return strings().voiceOverChatFailed
        case let .sent(read, played):
            var parts: [String] = []
            if read {
                parts.append(pluralRecipients ? strings().voiceOverChatSeenByRecipients : strings().voiceOverChatSeenByRecipient)
            }
            if let played = played {
                if played {
                    parts.append(pluralRecipients ? strings().voiceOverChatPlayedByRecipients : strings().voiceOverChatPlayedByRecipient)
                } else {
                    parts.append(pluralRecipients ? strings().voiceOverChatNotPlayedByRecipients : strings().voiceOverChatNotPlayedByRecipient)
                }
            }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
    }

    public var value: String {
        var lines: [String] = []
        if isSelected == true {
            lines.append(strings().voiceOverChatSelected)
        }
        let body = kindValue
        if !body.isEmpty {
            lines.append(body)
        }
        if !date.isEmpty {
            lines.append(date)
        }
        if let status = statusText {
            lines.append(status)
        }
        if let reply = reply, !reply.text.isEmpty {
            lines.append(strings().voiceOverChatReplyingToMessage(reply.text))
        }
        return lines.joined(separator: "\n")
    }

    public var help: String? {
        guard isSelected == nil else {
            return nil
        }
        switch kind {
        case .video, .voice, .roundVideo, .music:
            return strings().voiceOverChatPlayHint
        case .file:
            return strings().voiceOverChatOpenHint
        default:
            return nil
        }
    }
}

public extension ChatMessageAccessibility {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func kind(for message: Message) -> Kind {
        for media in message.media {
            if media is TelegramMediaImage {
                return .photo
            }
            if let file = media as? TelegramMediaFile {
                if file.isAnimatedSticker {
                    return .animatedSticker(emoji: file.stickerDisplayText)
                }
                if file.isSticker {
                    return .sticker(emoji: file.stickerDisplayText)
                }
                for attribute in file.attributes {
                    if case let .Audio(isVoice, duration, title, performer, _) = attribute {
                        if isVoice {
                            return .voice(duration: duration)
                        }
                        return .music(title: title, performer: performer, duration: duration)
                    }
                }
                if file.isInstantVideo {
                    return .roundVideo(duration: file.accessibilityDuration)
                }
                if file.isVideo {
                    return .video(duration: file.accessibilityDuration)
                }
                return .file(name: file.fileName, size: file.size)
            }
            if let contact = media as? TelegramMediaContact {
                let name = [contact.firstName, contact.lastName].filter { !$0.isEmpty }.joined(separator: " ")
                return .contact(name: name, phones: contact.phoneNumber.isEmpty ? [] : [contact.phoneNumber], organization: nil)
            }
            if let poll = media as? TelegramMediaPoll {
                let voters = poll.results.voters ?? []
                let total = Int(poll.results.totalVoters ?? 0)
                let voted = voters.contains(where: { $0.selected })
                let options = poll.options.map { option -> PollOption in
                    let entry = voters.first(where: { $0.opaqueIdentifier == option.opaqueIdentifier })
                    var percent: Int?
                    if (voted || poll.isClosed), total > 0, let count = entry?.count {
                        percent = Int((Double(count) / Double(total) * 100).rounded())
                    }
                    return PollOption(text: option.text, selected: entry?.selected ?? false, percent: percent)
                }
                return .poll(question: poll.text, anonymous: poll.publicity == .anonymous, options: options, votes: total, closed: poll.isClosed)
            }
            if let webpage = media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content {
                return .linkPreview(text: message.text, title: content.title ?? content.websiteName, description: content.text)
            }
        }
        return .text(message.text)
    }

    static func caption(for message: Message, kind: Kind) -> String? {
        switch kind {
        case .text, .linkPreview, .poll, .contact:
            return nil
        default:
            return message.text.isEmpty ? nil : message.text
        }
    }

    static func isConsumable(_ kind: Kind) -> Bool {
        switch kind {
        case .voice, .roundVideo:
            return true
        default:
            return false
        }
    }
}

private extension TelegramMediaFile {
    var accessibilityDuration: Int? {
        for attribute in attributes {
            if case let .Video(duration, _, _, _, _, _) = attribute {
                return Int(duration)
            }
        }
        return nil
    }

    var stickerDisplayText: String? {
        for attribute in attributes {
            if case let .Sticker(displayText, _, _) = attribute {
                return displayText
            }
        }
        return nil
    }
}
