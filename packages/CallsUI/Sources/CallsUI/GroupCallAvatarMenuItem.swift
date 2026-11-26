import Foundation
import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramMedia
import TelegramContext
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import Localization

private final class PhotoOrVideoView: View, SlideViewProtocol {
    private let imageView: TransformImageView
    
    
    private var photoVideoView: MediaPlayerView?
    private var photoVideoPlayer: MediaPlayer?

    private var videoView: NSView?
    
    public required init(frame frameRect: NSRect) {
        imageView = TransformImageView(frame: frameRect.size.bounds)
        super.init(frame: frameRect)
        addSubview(imageView)
    }
    
    public func willAppear() {
        
    }
    public func willDisappear() {
        
    }
    
    public override func layout() {
        super.layout()
        imageView.frame = bounds
        photoVideoView?.frame = imageView.frame
        videoView?.frame = imageView.frame
    }
    
    deinit {
    }
    
    public func setPeer(_ peer: Peer, peerPhoto: TelegramPeerPhoto?, video: NSView?, account: Account) {
        
        self.videoView = video
        
        if let video = video {
            self.photoVideoPlayer = nil
            self.photoVideoView?.removeFromSuperview()
            self.photoVideoView = nil
            addSubview(video)
        } else if let first = peerPhoto, let video = first.image.videoRepresentations.last {
            self.photoVideoView?.removeFromSuperview()
            self.photoVideoView = nil
            
            self.photoVideoView = MediaPlayerView(backgroundThread: true)
            
            addSubview(photoVideoView!, positioned: .above, relativeTo: self.imageView)
        
            self.photoVideoView!.isEventLess = true
            
            self.photoVideoView!.frame = self.imageView.frame
            
            let file = TelegramMediaFile(fileId: MediaId(namespace: 0, id: 0), partialReference: nil, resource: video.resource, previewRepresentations: first.image.representations, videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: video.resource.size, attributes: [], alternativeRepresentations: [])
            
            
            let mediaPlayer = MediaPlayer(postbox: account.postbox, userLocation: .peer(peer.id), userContentType: .avatar, reference: MediaResourceReference.standalone(resource: file.resource), streamable: true, video: true, preferSoftwareDecoding: false, enableSound: false, fetchAutomatically: true)
            
            mediaPlayer.actionAtEnd = .loop(nil)
            
            self.photoVideoPlayer = mediaPlayer
            
            if let seekTo = video.startTimestamp {
                mediaPlayer.seek(timestamp: seekTo)
            }
            mediaPlayer.attachPlayerView(self.photoVideoView!)
            mediaPlayer.play()
        } else {
            self.photoVideoPlayer = nil
            self.photoVideoView?.removeFromSuperview()
            self.photoVideoView = nil
            
            let profileImageRepresentations:[TelegramMediaImageRepresentation]
            if let peer = peer as? TelegramChannel {
                profileImageRepresentations = peer.profileImageRepresentations
            } else if let peer = peer as? TelegramUser {
                profileImageRepresentations = peer.profileImageRepresentations
            } else if let peer = peer as? TelegramGroup {
                profileImageRepresentations = peer.profileImageRepresentations
            } else {
                profileImageRepresentations = []
            }
            
            let id = profileImageRepresentations.first?.resource.id.hashValue ?? Int(peer.id.toInt64())
            let media = peerPhoto?.image ?? TelegramMediaImage(imageId: MediaId(namespace: 0, id: MediaId.Id(id)), representations: profileImageRepresentations, immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
                    
            
            if let dimension = profileImageRepresentations.last?.dimensions.size {
                let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: dimension, boundingSize: frame.size, intrinsicInsets: NSEdgeInsets())
                self.imageView.setSignal(signal: cachedMedia(media: media, arguments: arguments, scale: self.backingScaleFactor), clearInstantly: false)
                self.imageView.setSignal(chatMessagePhoto(account: account, imageReference: ImageMediaReference.standalone(media: media), peer: peer, scale: self.backingScaleFactor), clearInstantly: false, animate: true, cacheImage: { result in
                    cacheMedia(result, media: media, arguments: arguments, scale: System.backingScale)
                })
                self.imageView.set(arguments: arguments)
                
                if let reference = PeerReference(peer) {
                    _ = fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .peer(peer.id), userContentType: .image, reference: .avatar(peer: reference, resource: media.representations.last!.resource)).start()
                }
            } else {
                self.imageView.setSignal(signal: generateEmptyRoundAvatar(self.imageView.frame.size, font: .avatar(90.0), account: account, peer: peer) |> map { TransformImageResult($0, true) })
            }
        }
     
    }
    
        
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


public final class GroupCallAvatarMenuItem : ContextMenuItem {
    private let peer: Peer
    private let context: any AccountContextProtocol
    public init(_ peer: Peer, context: any AccountContextProtocol) {
        self.peer = peer
        self.context = context
        super.init("")
    }
    
    public required init(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    public override func rowItem(presentation: AppMenu.Presentation, interaction: AppMenuBasicItem.Interaction) -> TableRowItem {
        return GroupCallAvatarMenuRowItem(.zero, presentation: presentation, interaction: interaction, peer: peer, context: context)
    }
}


private final class GroupCallAvatarMenuRowItem : AppMenuBasicItem {
    fileprivate let peer: Peer
    fileprivate let context: any AccountContextProtocol
    public init(_ initialSize: NSSize, presentation: AppMenu.Presentation, interaction: AppMenuBasicItem.Interaction, peer: Peer, context: any AccountContextProtocol) {
        self.peer = peer
        self.context = context
        super.init(initialSize, presentation: presentation, menuItem: nil, interaction: interaction)
    }
    
    public override func viewClass() -> AnyClass {
        return GroupCallAvatarMenuRowView.self
    }
    
    public override var effectiveSize: NSSize {
        return NSMakeSize(200, 200)
    }
    
    public override var height: CGFloat {
        return 200
    }

    public override var accessibilityLabel: String? {
        return strings().voiceOverCommonPhotoOf(peer.displayTitle)
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .image
    }
}


private final class GroupCallAvatarMenuRowView : AppMenuBasicItemView {
    private let slider: SliderView = SliderView(frame: .zero)
    private let sliderMask: CAShapeLayer = CAShapeLayer()
    private let peerPhotosDisposable = MetaDisposable()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(slider)
        slider.layer?.mask = sliderMask
    }

    deinit {
        peerPhotosDisposable.dispose()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    public override func layout() {
        super.layout()

        slider.setFrameSize(NSMakeSize(contentSize.width, contentSize.height - 4))
        updateSliderMask()
    }

    private func updateSliderMask() {
        let bounds = slider.bounds
        let topRadius: CGFloat = 4
        let bottomRadius: CGFloat = 16
        let path = CGMutablePath()
        path.move(to: CGPoint(x: bounds.minX + topRadius, y: bounds.maxY))
        path.addLine(to: CGPoint(x: bounds.maxX - topRadius, y: bounds.maxY))
        path.addArc(tangent1End: CGPoint(x: bounds.maxX, y: bounds.maxY), tangent2End: CGPoint(x: bounds.maxX, y: bounds.maxY - topRadius), radius: topRadius)
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.minY + bottomRadius))
        path.addArc(tangent1End: CGPoint(x: bounds.maxX, y: bounds.minY), tangent2End: CGPoint(x: bounds.maxX - bottomRadius, y: bounds.minY), radius: bottomRadius)
        path.addLine(to: CGPoint(x: bounds.minX + bottomRadius, y: bounds.minY))
        path.addArc(tangent1End: CGPoint(x: bounds.minX, y: bounds.minY), tangent2End: CGPoint(x: bounds.minX, y: bounds.minY + bottomRadius), radius: bottomRadius)
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.maxY - topRadius))
        path.addArc(tangent1End: CGPoint(x: bounds.minX, y: bounds.maxY), tangent2End: CGPoint(x: bounds.minX + topRadius, y: bounds.maxY), radius: topRadius)
        path.closeSubpath()
        sliderMask.path = path
        sliderMask.frame = bounds
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? GroupCallAvatarMenuRowItem else {
            return
        }
        
        let peer = item.peer
        let context = item.context
        
        var photos = Array(syncPeerPhotos(peerId: peer.id).prefix(10))
        let signal = peerPhotos(context: context, peerId: peer.id, force: true) |> deliverOnMainQueue
                
        
        slider.frame = NSMakeRect(0, 0, frame.width - 8, frame.height - 4)
        
        let view = PhotoOrVideoView(frame: self.slider.bounds)
        view.setPeer(peer, peerPhoto: nil, video: nil, account: context.account)
        self.slider.addSlide(view)
        
        if photos.isEmpty {
            
            peerPhotosDisposable.set(signal.start(next: { [weak self, weak view] photos in
                guard let `self` = self else {
                    return
                }
                
                var photos = Array(photos.prefix(10))
                
                if !photos.isEmpty {
                    let first = photos.removeFirst()
                    if !first.value.image.videoRepresentations.isEmpty {
                        photos.insert(first, at: 0)
                        self.slider.removeSlide(view)
                    }
                }
                for photo in photos {
                    let view = PhotoOrVideoView(frame: self.slider.bounds)
                    view.setPeer(peer, peerPhoto: photo.value, video: nil, account: context.account)
                    self.slider.addSlide(view)
                }
            }))
        } else {
            if !photos.isEmpty {
                let first = photos.removeFirst()
                if !first.value.image.videoRepresentations.isEmpty {
                    photos.insert(first, at: 0)
                    self.slider.removeSlide(view)
                }
            }
            for photo in photos {
                let view = PhotoOrVideoView(frame: self.slider.bounds)
                view.setPeer(peer, peerPhoto: photo.value, video: nil, account: context.account)
                self.slider.addSlide(view)
            }
        }    }
}
