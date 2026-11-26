import Foundation
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Postbox
import TelegramContext

public struct StoryCellLayoutItem : Equatable, MediaCellLayoutable {
    
    
    public static func == (lhs: StoryCellLayoutItem, rhs: StoryCellLayoutItem) -> Bool {
        return lhs.item == rhs.item && lhs.corners == rhs.corners && lhs.frame == rhs.frame
    }
    public let item: StoryListContextState.Item
    public let peerReference: PeerReference
    public let peerId: PeerId
    public let frame: NSRect
    public let viewType:MediaCell.Type
    public let corners:ImageCorners
    public let context: any AccountContextProtocol
    public let isPinned: Bool
    public init(item: StoryListContextState.Item, peerReference: PeerReference, peerId: PeerId, frame: NSRect, viewType: MediaCell.Type, corners: ImageCorners, context: any AccountContextProtocol, isPinned: Bool) {
        self.item = item
        self.peerReference = peerReference
        self.peerId = peerId
        self.frame = frame
        self.viewType = viewType
        self.corners = corners
        self.context = context
        self.isPinned = isPinned
    }
    public var isSecret: Bool {
        return false
    }
    
    public var isSensitive: Bool {
        return false
    }
    
    public var isSpoiler: Bool {
        return false
    }
    
    public var id: MessageId {
        return .init(peerId: self.peerId, namespace: 0, id: self.item.storyItem.id)
    }
    
    
    public var imageMedia: ImageMediaReference? {
        if let image = self.item.storyItem.media._asMedia() as? TelegramMediaImage {
            return .story(peer: peerReference, id: self.item.storyItem.id, media: image)
        }
        return nil
    }
    
    public var fileMedia: FileMediaReference? {
        if let file = self.item.storyItem.media._asMedia() as? TelegramMediaFile {
            return .story(peer: peerReference, id: self.item.storyItem.id, media: file)
        }
        return nil
    }
    
    public func isEqual(to: MediaCellLayoutable) -> Bool {
        if let to = to as? StoryCellLayoutItem {
            return to == self
        }
        return false
    }
    
    public func makeImageReference(_ image: TelegramMediaImage) -> ImageMediaReference {
        return .story(peer: self.peerReference, id: self.item.storyItem.id, media: image)
    }
    
    public func makeFileReference(_ file: TelegramMediaFile) -> FileMediaReference {
        return .story(peer: self.peerReference, id: self.item.storyItem.id, media: file)
    }
    
    public var hasImmediateData: Bool {
        if let image = item.storyItem.media._asMedia() as? TelegramMediaImage {
            return image.immediateThumbnailData != nil
        } else if let file = item.storyItem.media._asMedia() as? TelegramMediaFile {
            return file.immediateThumbnailData != nil
        }
        return false
    }
}
