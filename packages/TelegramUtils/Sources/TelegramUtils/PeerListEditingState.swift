import Foundation
import Postbox

public struct PeerListEditingState: Equatable {
    public let editing: Bool
    public let removingPeerId: PeerId?
    
    public init() {
        self.editing = false
        self.removingPeerId = nil
    }
    
    public init(editing: Bool, removingPeerId: PeerId?) {
        self.editing = editing
        self.removingPeerId = removingPeerId
    }
    
    public func withUpdatedEditing(_ editing: Bool) -> PeerListEditingState {
        return PeerListEditingState(editing: editing, removingPeerId: self.removingPeerId)
    }
    
    public func withUpdatedRemovingPeerId(_ removingPeerId: PeerId?) -> PeerListEditingState {
        return PeerListEditingState(editing: self.editing, removingPeerId: removingPeerId)
    }
}
