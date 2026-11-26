import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils


private enum PeerAvatarReference : Equatable {
    static func == (lhs: PeerAvatarReference, rhs: PeerAvatarReference) -> Bool {
        switch lhs {
        case let .image(lhsPeer, rep):
            if case .image(let rhsPeer, rep) = rhs {
                return lhsPeer.isEqual(rhsPeer)
            } else {
                return false
            }
        }
    }
    
    case image(Peer, TelegramMediaImageRepresentation?)
    
    var peerId: PeerId {
        switch self {
        case let .image(value, _):
            return value.id
        }
    }
}

private extension PeerAvatarReference {
    init(peer: Peer) {
        self = .image(peer, peer.smallProfileImage)
    }
}



public final class MergedAvatarsView: Control {
    
    public init(mergedImageSize: CGFloat = 16.0, mergedImageSpacing: CGFloat = 15.0, avatarFont: NSFont = NSFont.avatar(8.0)) {
        self.mergedImageSize = mergedImageSize
        self.mergedImageSpacing = mergedImageSpacing
        self.avatarFont = avatarFont
        super.init()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required convenience init(frame frameRect: NSRect) {
        self.init()
    }
    
    public let mergedImageSize: CGFloat
    public let mergedImageSpacing: CGFloat
    
    public let avatarFont: NSFont
    
    private var peers: [PeerAvatarReference] = []
    private var images: [PeerId: CGImage] = [:]
    private var disposables: [PeerId: Disposable] = [:]
    
    
    deinit {
        for (_, disposable) in self.disposables {
            disposable.dispose()
        }
    }
    
    public func update(context: any AccountContextProtocol, peers: [Peer], message: Message?, synchronousLoad: Bool) {
        let filteredPeers = Array(peers.map(PeerAvatarReference.init).prefix(3))
        
        if filteredPeers != self.peers {
            self.peers = filteredPeers
            
            var validImageIds: [PeerId] = []
            for peer in filteredPeers {
                if case .image = peer {
                    validImageIds.append(peer.peerId)
                }
            }
            
            var removedImageIds: [PeerId] = []
            for (id, _) in self.images {
                if !validImageIds.contains(id) {
                    removedImageIds.append(id)
                }
            }
            var removedDisposableIds: [PeerId] = []
            for (id, disposable) in self.disposables {
                if !validImageIds.contains(id) {
                    disposable.dispose()
                    removedDisposableIds.append(id)
                }
            }
            for id in removedImageIds {
                self.images.removeValue(forKey: id)
            }
            for id in removedDisposableIds {
                self.disposables.removeValue(forKey: id)
            }
            for peer in filteredPeers {
                switch peer {
                case let .image(peer, representation):
                    if self.disposables[peer.id] == nil {
                        let signal = peerAvatarImage(account: context.account, photo: PeerPhoto.peer(peer, representation, peer.namePeerColor, TelegramUtilsHooks.shared.peerLetters(peer), message, nil), displayDimensions: NSMakeSize(mergedImageSize, mergedImageSize), scale: backingScaleFactor, font: avatarFont, synchronousLoad: synchronousLoad)
                        let disposable = (signal
                            |> deliverOnMainQueue).start(next: { [weak self] image in
                                guard let strongSelf = self else {
                                    return
                                }
                                if let image = image.0 {
                                    strongSelf.images[peer.id] = image
                                    strongSelf.setNeedsDisplay()
                                }
                            })
                        self.disposables[peer.id] = disposable
                    }
                }
            }
            self.setNeedsDisplay()
        }
    }
    
    public override func draw(_ layer: CALayer, in context: CGContext) {
        super.draw(layer, in: context)
        
        
        context.setBlendMode(.copy)
        context.setFillColor(NSColor.clear.cgColor)
        context.fill(bounds)
        
        
        context.setBlendMode(.copy)
        
        var currentX = mergedImageSize + mergedImageSpacing * CGFloat(self.peers.count - 1) - mergedImageSize
        for i in (0 ..< self.peers.count).reversed() {
            context.saveGState()
            
            context.translateBy(x: frame.width / 2.0, y: frame.height / 2.0)
            context.scaleBy(x: 1.0, y: -1.0)
            context.translateBy(x: -frame.width / 2.0, y: -frame.height / 2.0)
            
            let imageRect = CGRect(origin: CGPoint(x: currentX, y: 0.0), size: CGSize(width: mergedImageSize, height: mergedImageSize))
            context.setFillColor(NSColor.clear.cgColor)
            context.fillEllipse(in: imageRect.insetBy(dx: -1.0, dy: -1.0))
            
            if let image = self.images[self.peers[i].peerId] {
                context.draw(image, in: imageRect)
            } else {
                context.setFillColor(NSColor.gray.cgColor)
                context.fillEllipse(in: imageRect)
            }
            
            currentX -= mergedImageSpacing
            context.restoreGState()
        }
    }
}

