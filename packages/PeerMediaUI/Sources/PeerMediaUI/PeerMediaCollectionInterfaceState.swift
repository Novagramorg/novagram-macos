import Cocoa
import TelegramCore

import Postbox
import TGUIKit
import ChatHistoryModel
import TelegramLinks



public struct PeerMediaCollectionInterfaceState: Equatable {
    public let peer: Peer?
    public let selectionState: ChatInterfaceSelectionState?
    public let mode: PeerMediaCollectionMode
    public let selectingMode: Bool
    
    public init() {
        self.peer = nil
        self.selectionState = nil
        self.mode = .photoOrVideo
        self.selectingMode = false
    }
    
    public init(peer: Peer?, selectionState: ChatInterfaceSelectionState?, mode: PeerMediaCollectionMode, selectingMode: Bool) {
        self.peer = peer
        self.selectionState = selectionState
        self.mode = mode
        self.selectingMode = selectingMode
    }
    
    public static func ==(lhs: PeerMediaCollectionInterfaceState, rhs: PeerMediaCollectionInterfaceState) -> Bool {
        if let peer = lhs.peer {
            if rhs.peer == nil || !peer.isEqual(rhs.peer!) {
                return false
            }
        } else if let _ = rhs.peer {
            return false
        }
        
        if lhs.selectionState != rhs.selectionState {
            return false
        }
        
        if lhs.mode != rhs.mode {
            return false
        }
        
        if lhs.selectingMode != rhs.selectingMode {
            return false
        }
        
        return true
    }
    
   
    
    public func isSelectedMessageId(_ messageId:MessageId) -> Bool {
        if let selectionState = selectionState {
            return selectionState.selectedIds.contains(messageId)
        }
        return false
    }
    
    public func withUpdatedSelectedMessage(_ messageId: MessageId) -> PeerMediaCollectionInterfaceState {
        var selectedIds = Set<MessageId>()
        if let selectionState = self.selectionState {
            selectedIds.formUnion(selectionState.selectedIds)
        }
        selectedIds.insert(messageId)
        return PeerMediaCollectionInterfaceState(peer: self.peer, selectionState: ChatInterfaceSelectionState(selectedIds: selectedIds, lastSelectedId: nil), mode: self.mode, selectingMode: self.selectingMode)
    }
    
    public func withToggledSelectedMessage(_ messageId: MessageId) -> PeerMediaCollectionInterfaceState {
        var selectedIds = Set<MessageId>()
        if let selectionState = self.selectionState {
            selectedIds.formUnion(selectionState.selectedIds)
        }
        if selectedIds.contains(messageId) {
            let _ = selectedIds.remove(messageId)
        } else {
            selectedIds.insert(messageId)
        }
        return PeerMediaCollectionInterfaceState(peer: self.peer, selectionState: ChatInterfaceSelectionState(selectedIds: selectedIds, lastSelectedId: nil), mode: self.mode, selectingMode: self.selectingMode)
    }
    
    public func withSelectionState() -> PeerMediaCollectionInterfaceState {
        return PeerMediaCollectionInterfaceState(peer: self.peer, selectionState: self.selectionState ?? ChatInterfaceSelectionState(selectedIds: Set(), lastSelectedId: nil), mode: self.mode, selectingMode: true)
    }
    
    public func withoutSelectionState() -> PeerMediaCollectionInterfaceState {
        return PeerMediaCollectionInterfaceState(peer: self.peer, selectionState: nil, mode: self.mode, selectingMode: false)
    }
    
    public func withUpdatedPeer(_ peer: Peer?) -> PeerMediaCollectionInterfaceState {
        return PeerMediaCollectionInterfaceState(peer: peer, selectionState: self.selectionState, mode: self.mode, selectingMode: self.selectingMode)
    }
    
    public func withMode(_ mode: PeerMediaCollectionMode) -> PeerMediaCollectionInterfaceState {
        return PeerMediaCollectionInterfaceState(peer: self.peer, selectionState: self.selectionState, mode: mode, selectingMode: self.selectingMode)
    }
}

