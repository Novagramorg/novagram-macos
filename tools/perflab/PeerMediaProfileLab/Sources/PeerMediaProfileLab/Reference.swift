import Cocoa

import SwiftSignalKit

func referenceConvertEntries(from update: PeerMediaUpdate, tags: MessageTags, timeDifference: TimeInterval, isExternalSearch: Bool) -> [PeerMediaSharedEntry] {
    var converted:[PeerMediaSharedEntry] = []


    struct Item {
        let date: PeerMediaSharedEntry
        let section: PeerMediaSharedEntry
        let items:[PeerMediaSharedEntry]
        init(_ date: PeerMediaSharedEntry, _ section: PeerMediaSharedEntry, _ items: [PeerMediaSharedEntry]) {
            self.date = date
            self.section = section
            self.items = items.sorted(by: >)
        }
    }


    var tempItems:[(PeerMediaSharedEntry, PeerMediaSharedEntry?)] = []

    let messages = expandSharedMediaMessages(update.messages, where: sharedMediaPredicate(for: tags))

    for i in 0 ..< messages.count {

        let message = messages[i]

        let next = i < messages.count - 1 ? messages[i + 1] : nil



        if let nextMessage = next {

            let timestamp = Int32(min(TimeInterval(message.timestamp) - timeDifference, TimeInterval(Int32.max)))
            let nextTimestamp = Int32(min(TimeInterval(nextMessage.timestamp) - timeDifference, TimeInterval(Int32.max)))


            let dateId = mediaDateId(for: timestamp)
            let nextDateId = mediaDateId(for: nextTimestamp)
            if dateId != nextDateId {
                let index = MessageIndex(id: message.id, timestamp: Int32(dateId))
                tempItems.append((.date(index), .sectionId(index.peerLocalSuccessor())))
            }
        } else {
            let timestamp = Int32(min(TimeInterval(message.timestamp) - timeDifference, TimeInterval(Int32.max)))
            let dateId = mediaDateId(for: timestamp)
            let index = MessageIndex(id: message.id, timestamp: Int32(dateId))
            tempItems.append((.date(index), .sectionId(index.peerLocalSuccessor())))
        }
        tempItems.append((.messageEntry(message, isExternalSearch ? update.messages : [], update.automaticDownload, .singleItem), nil))

    }


    var groupItems:[Item] = []
    var current:[PeerMediaSharedEntry] = []
    for item in tempItems.sorted(by: { $0.0 < $1.0 }) {
        switch item.0 {
        case .date:
            if !current.isEmpty {
                groupItems.append(Item(item.0, item.1!, current))
                current.removeAll()
            }
        case .messageEntry:
            current.insert(item.0, at: 0)
        default:
            fatalError()
        }
    }

    if !current.isEmpty {
        if !groupItems.isEmpty {
            let item = groupItems.last!
            groupItems[groupItems.count - 1] = Item(item.date, item.section, item.items + current)
        } else {
            groupItems.append(.init(current.first!, .sectionId(current.first!.index.peerLocalSuccessor()), current))
        }
    }


    for (i, group) in groupItems.reversed().enumerated() {
        if i != 0 {
            converted.append(group.date)
        }


        for item in group.items {
            switch item {
            case let .messageEntry(message, messages, settings, _):
                var viewType = bestGeneralViewType(group.items, for: item)

                if i == 0, item == group.items.first {
                    if group.items.count > 1 {
                        viewType = .innerItem
                    } else {
                        viewType = .lastItem
                    }
                }

                converted.append(.messageEntry(message, messages, settings, viewType))
            default:
                fatalError()
            }
        }
    }



    if !tempItems.isEmpty {
    }

    if update.updateType == .search {
        if converted.isEmpty {
            converted.append(.emptySearchEntry(false))
        }
    } else if update.updateType == .loading {
        if converted.isEmpty {
            converted.append(.emptySearchEntry(true))
        }
    }
    converted = converted.sorted(by: <)



    return converted
}


struct ReferenceGifsState : Equatable {
    let isLoading: Bool
    let messages:[Message]
    init(isLoading: Bool, messages: [Message]) {
        self.isLoading = isLoading
        self.messages = messages.reversed()
    }
    func withUpdatedMessages(_ collection: [Message]) -> ReferenceGifsState {
        return ReferenceGifsState(isLoading: self.isLoading, messages: collection)
    }
    func withUpdatedLoading(_ isLoading: Bool) -> ReferenceGifsState {
        return ReferenceGifsState(isLoading: isLoading, messages: self.messages)
    }
}


struct ReferencePhotosState : Equatable {
    static func == (lhs: ReferencePhotosState, rhs: ReferencePhotosState) -> Bool {
        return lhs.isLoading == rhs.isLoading && lhs.messages == rhs.messages && lhs.searchState == rhs.searchState && lhs.contentSettings == rhs.contentSettings && lhs.scrollPosition == rhs.scrollPosition && lhs.updateType == rhs.updateType && lhs.side == rhs.side && lhs.perRowCount == rhs.perRowCount
    }

    var isLoading: Bool
    var messages:[Message]
    var searchState: SearchState
    var contentSettings: ContentSettings
    var scrollPosition: ChatHistoryViewScrollPosition?
    var updateType: ChatHistoryViewUpdateType?
    var side: TableSavingSide?
    var view: MessageHistoryView?
    var perRowCount: Int
    init(isLoading: Bool, messages: [Message], searchState: SearchState, contentSettings: ContentSettings, scrollPosition: ChatHistoryViewScrollPosition?, updateType: ChatHistoryViewUpdateType?, side: TableSavingSide?, perRowCount: Int) {
        self.isLoading = isLoading
        self.messages = messages.reversed().filter { $0.restrictedText(contentSettings) == nil }
        self.searchState = searchState
        self.contentSettings = contentSettings
        self.updateType = updateType
        self.scrollPosition = scrollPosition
        self.side = side
        self.perRowCount = perRowCount
    }
}


func referenceActivities(_ signal: Signal<[(PeerId, PeerInputActivity)], NoError>) -> Signal<[PeerId: PeerInputActivity], NoError> {
return signal
            |> map { activities -> [PeerId : PeerInputActivity] in
                return activities.reduce([:], { (current, activity) -> [PeerId : PeerInputActivity] in
                    var current = current
                    current[activity.0] = activity.1
                    return current
                })
        }


}
