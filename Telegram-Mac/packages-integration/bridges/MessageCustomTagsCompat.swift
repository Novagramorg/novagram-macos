import Foundation
import TelegramCore
import Postbox

extension Message {
    func withUpdatedTimestamp(_ timestamp: Int32) -> Message {
        return Message(stableId: self.stableId, stableVersion: self.stableVersion, id: self.id, globallyUniqueId: self.globallyUniqueId, groupingKey: self.groupingKey, groupInfo: self.groupInfo, threadId: threadId, timestamp: timestamp, flags: self.flags, tags: self.tags, globalTags: self.globalTags, localTags: self.localTags, customTags: [], forwardInfo: self.forwardInfo, author: self.author, text: self.text, attributes: self.attributes, media: self.media, peers: self.peers, associatedMessages: self.associatedMessages, associatedMessageIds: self.associatedMessageIds, associatedMedia: self.associatedMedia, associatedThreadInfo: self.associatedThreadInfo, associatedStories: self.associatedStories)
    }

    func withUpdatedText(_ text:String) -> Message {
        return Message(stableId: stableId, stableVersion: stableVersion, id: id, globallyUniqueId: globallyUniqueId, groupingKey: groupingKey, groupInfo: groupInfo, threadId: threadId, timestamp: timestamp, flags: flags, tags: tags, globalTags: globalTags, localTags: localTags, customTags: [], forwardInfo: forwardInfo, author: author, text: text, attributes: attributes, media: media, peers: peers, associatedMessages: associatedMessages, associatedMessageIds: associatedMessageIds, associatedMedia: self.associatedMedia, associatedThreadInfo: self.associatedThreadInfo, associatedStories: self.associatedStories)
    }
}
