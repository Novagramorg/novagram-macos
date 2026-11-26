import TelegramCore

import Postbox


public func isEqualMessages(_ lhsMessage: Message, _ rhsMessage: Message) -> Bool {

    // Same instance → identical by definition. Hits often when the same
    // Message reference reappears in two diffs.
    if lhsMessage === rhsMessage {
        return true
    }

    // Cheapest discriminators first — id and stableVersion catch almost every
    // real "messages differ" case in one Int compare.
    if lhsMessage.id != rhsMessage.id {
        return false
    }
    if lhsMessage.stableVersion != rhsMessage.stableVersion {
        return false
    }

    if lhsMessage.derivedDataAttribute?.data != rhsMessage.derivedDataAttribute?.data {
        return false
    }
    if lhsMessage.forwardVideoTimestampAttribute?.timestamp != rhsMessage.forwardVideoTimestampAttribute?.timestamp {
        return false
    }

    // `media` is a plain `[Media]`, indexed access is O(1).
    if lhsMessage.media.count != rhsMessage.media.count {
        return false
    }
    for i in 0 ..< lhsMessage.media.count {
        if !lhsMessage.media[i].isEqual(to: rhsMessage.media[i]) {
            return false
        }
    }

    // `associatedMessages` / `peers` are SimpleDictionary, whose subscript is
    // a linear scan over `items`. Iterating one side and subscripting the
    // other was O(n²); convert one side to a Swift `[K: V]` once for O(1)
    // lookups inside the loop.
    let lhsAssocCount = lhsMessage.associatedMessages.count
    if lhsAssocCount != rhsMessage.associatedMessages.count {
        return false
    }
    if lhsAssocCount > 0 {
        var lhsAssoc: [MessageId: Message] = [:]
        lhsAssoc.reserveCapacity(lhsAssocCount)
        for (k, v) in lhsMessage.associatedMessages {
            lhsAssoc[k] = v
        }
        for (messageId, rhsAssociatedMessage) in rhsMessage.associatedMessages {
            guard let lhsAssociatedMessage = lhsAssoc[messageId] else {
                return false
            }
            if !isEqualMessages(lhsAssociatedMessage, rhsAssociatedMessage) {
                return false
            }
        }
    }

    // `associatedStories` is already a real `[StoryId: CodableEntry]`, so
    // subscript is O(1). Keep the existing structure but skip the iteration
    // entirely when both are empty.
    let lhsStoriesCount = lhsMessage.associatedStories.count
    if lhsStoriesCount != rhsMessage.associatedStories.count {
        return false
    }
    if lhsStoriesCount > 0 {
        for (storyId, lhsAssociatedStory) in lhsMessage.associatedStories {
            guard let rhsAssociatedStory = rhsMessage.associatedStories[storyId] else {
                return false
            }
            // Fast path: the underlying CodableEntry data hasn't changed.
            if lhsAssociatedStory == rhsAssociatedStory {
                continue
            }
            let lhsStory = lhsAssociatedStory.get(Stories.StoredItem.self)
            let rhsStory = rhsAssociatedStory.get(Stories.StoredItem.self)
            if lhsStory != rhsStory {
                return false
            }
        }
    }

    let lhsPeersCount = lhsMessage.peers.count
    if lhsPeersCount != rhsMessage.peers.count {
        return false
    }
    if lhsPeersCount > 0 {
        var lhsPeers: [PeerId: Peer] = [:]
        lhsPeers.reserveCapacity(lhsPeersCount)
        for (k, v) in lhsMessage.peers {
            lhsPeers[k] = v
        }
        for (rhsPeerId, rhsPeer) in rhsMessage.peers {
            guard let lhsPeer = lhsPeers[rhsPeerId] else {
                return false
            }
            if lhsPeer.displayTitle != rhsPeer.displayTitle {
                return false
            }
        }
    }

    return true
}
