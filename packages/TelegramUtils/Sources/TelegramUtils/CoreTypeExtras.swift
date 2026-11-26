import Foundation
import CalendarUtils
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
import Localization

public extension RenderedPeer {
    convenience init(_ foundPeer: FoundPeer) {
        let peer = foundPeer.peer._asPeer()
        self.init(peerId: peer.id, peers: SimpleDictionary([peer.id : peer]), associatedMedia: [:])
    }
}

public extension ChatContextResult {
    var maybeId:Int64 {
        var t:String = ""
        var d:String = ""
        if let title = title {
            t = title
        }
        if let description = description {
            d = description
        }
        let maybe = id + type + t + d
        return Int64(maybe.hash)
    }
}

public extension PeerView {
    var isMuted:Bool {
        if let settings = self.notificationSettings as? TelegramPeerNotificationSettings {
            switch settings.muteState {
            case let .muted(until):
                return until > Int32(Date().timeIntervalSince1970)
            case .unmuted:
                return false
            case .default:
                return false
            }
        } else {
            return false
        }
    }
}

public extension TelegramPeerNotificationSettings {
    var isMuted:Bool {
        switch self.muteState {
        case let .muted(until):
            return until > Int32(Date().timeIntervalSince1970)
        case .unmuted:
            return false
        case .default:
            return false
        }
    }
}

public extension AvailableReactions {
    var enabled: [AvailableReactions.Reaction] {
        return self.reactions.filter { $0.isEnabled }
    }
}

public extension SuggestedLocalizationInfo {
    func localizedKey(_ key:String) -> String {
        for entry in extractedEntries {
            switch entry {
            case let.string(_key, _value):
                if _key == key {
                    return _value
                }
            default:
                break
            }
        }
        return NSLocalizedString(key, comment: "")
    }
}

public extension TelegramGroup {
    var canPinMessage: Bool {
        return !hasBannedRights(.banPinMessages)
    }
}

public extension Signal {
    
    static func next(_ value: T) -> Signal<T, E> {
        return Signal<T, E> { subscriber in
            subscriber.putNext(value)
            
            return EmptyDisposable
        }
    }
}

public func isNotEmptyStrings(_ strings: [String?]) -> String {
    for string in strings {
        if let string = string, !string.isEmpty {
            return string
        }
    }
    return ""
}

public extension CachedChannelData.LinkedDiscussionPeerId {
    var peerId: PeerId? {
        switch self {
        case let .known(peerId):
            return peerId
        case .unknown:
            return nil
        }
    }
}

public extension CachedPeerAutoremoveTimeout {
    var timeout: CachedPeerAutoremoveTimeout.Value? {
        switch self {
        case let .known(timeout):
            return timeout
        case .unknown:
            return nil
        }
    }

}

public extension RenderedPeer {
    convenience init(_ renderedPeer: EngineRenderedPeer) {
        let dict = SimpleDictionary<PeerId, any Peer>(renderedPeer.peers.mapValues {
            $0._asPeer()
        })
        self.init(peerId: renderedPeer.peerId, peers: dict, associatedMedia: renderedPeer.associatedMedia)
    }
}

public extension Date {
    var birthday: TelegramBirthday {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.component(.day, from: self)
        let month = calendar.component(.month, from: self)
        let year = calendar.component(.year, from: self)
        
        return TelegramBirthday(day: Int32(day), month: Int32(month), year: CalendarUtils.isYearHidden(year) ? nil : Int32(year))
    }
}

public extension EngineStoryItem {
    var isLiveStream: Bool {
        switch self.media {
        case .liveStream:
            return true
        default:
            return false
        }
    }
}
