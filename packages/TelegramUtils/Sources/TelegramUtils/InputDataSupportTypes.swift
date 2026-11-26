import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import TGUIKit
import Localization

public let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd.MM.yyyy"
   // formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

public protocol PeerMediaSearchable : AnyObject {
    func toggleSearch()
    func setSearchValue(_ value: Signal<SearchState, NoError>)
    func setExternalSearch(_ value: Signal<ExternalSearchMessages?, NoError>, _ loadMore: @escaping()->Void)
    var mediaSearchValue:Signal<MediaSearchState, NoError> { get }
 }

public struct MediaSearchState : Equatable {
    public let state: SearchState
    public let animated: Bool
    public let isLoading: Bool
    public init(state: SearchState, animated: Bool, isLoading: Bool) {
        self.state = state
        self.animated = animated
        self.isLoading = isLoading
    }
}

public struct ExternalSearchMessages {
    public let messages:[Message]
    public let count: Int32
    public let tags: MessageTags?
    public init(messages: [Message] = [], count: Int32 = 0, tags: MessageTags? = nil) {
        self.messages = messages
        self.count = count
        self.tags = tags
    }
    public var title: String? {
        let text: String?
        if tags == .photoOrVideo {
            text = strings().peerMediaTitleSearchMediaOther(Int(count))
        } else if tags == .photo {
            text = strings().peerMediaTitleSearchPhotosOther(Int(count))
        } else if tags == .video {
            text = strings().peerMediaTitleSearchVideosOther(Int(count))
        } else if tags == .gif {
            text = strings().peerMediaTitleSearchGIFsOther(Int(count))
        } else if tags == .file {
            text = strings().peerMediaTitleSearchFilesOther(Int(count))
        } else if tags == .webPage {
            text = strings().peerMediaTitleSearchLinksOther(Int(count))
        } else if tags == .music {
            text = strings().peerMediaTitleSearchMusicOther(Int(count))
        } else {
            text = nil
        }
        if let text = text {
            return text.replacingOccurrences(of: "\(count)", with: count.formattedWithSeparator)
        }
        return text
    }
}
