import Foundation
import Postbox
import TelegramCore

public enum PeerMediaCollectionMode : Int32 {
    case stories = -6
    case gifts = -5
    case savedMessages = -4
    case members = -3
    case archiveStories = -2
    case photoOrVideo = -1
    case saved = 0
    case file = 1
    case webpage = 2
    case music = 3
    case voice = 4
    case gifs = 5
    case commonGroups = 6
    case similarChannels = 7
    case similarBots = 8
    case polls = 9
    public var tagsValue:MessageTags {
        switch self {
        case .photoOrVideo:
            return .photoOrVideo
        case .file:
            return .file
        case .music:
            return .music
        case .webpage:
            return .webPage
        case .voice:
            return .voiceOrInstantVideo
        case .members:
           return []
        case .commonGroups:
            return []
        case .gifs:
            return .gif
        case .stories:
            return []
        case .archiveStories:
            return []
        case .similarChannels:
            return []
        case .similarBots:
            return []
        case .savedMessages:
            return []
        case .saved:
            return []
        case .gifts:
            return []
        case .polls:
            return .polls
        }
    }
}
