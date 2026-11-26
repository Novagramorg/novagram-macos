import Foundation

public struct ChatTitleCounters : Equatable {
    public var replies: Int32?
    public var online: Int32?
    public init(replies: Int32? = nil, online: Int32? = nil) {
        self.replies = replies
        self.online = online
    }
}
