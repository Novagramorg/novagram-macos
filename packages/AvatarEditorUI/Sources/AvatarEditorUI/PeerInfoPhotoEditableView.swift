import Cocoa
import TGUIKit
import TelegramTheme
import Localization

public final class PeerInfoUpdatingPhotoState : Equatable {
    public let progress:Float
    public let cancel:()->Void
    public let image: CGImage?
    public init(progress: Float, image: CGImage? = nil, cancel: @escaping()->Void) {
        self.progress = progress
        self.cancel = cancel
        self.image = image
    }
    public func withUpdatedImage(_ image: CGImage) -> PeerInfoUpdatingPhotoState {
        return PeerInfoUpdatingPhotoState(progress: progress, image: image, cancel: self.cancel)
    }
    
    public func withUpdatedProgress(_ progress: Float) -> PeerInfoUpdatingPhotoState {
        return PeerInfoUpdatingPhotoState(progress: progress, image: self.image, cancel: self.cancel)
    }
    
    public static func ==(lhs:PeerInfoUpdatingPhotoState, rhs: PeerInfoUpdatingPhotoState) -> Bool {
        return lhs.progress == rhs.progress && lhs.image == rhs.image
    }
}

public final class PeerInfoPhotoEditableView : Control {
    private let backgroundView = View(frame: .zero)
    private let camera: ImageView = ImageView()
    private var progressView:RadialProgressContainerView?
    private var updatingPhotoState: PeerInfoUpdatingPhotoState?
    private var tempImageView: ImageView?
    public var setup: ((NSImage?, Control?)->Void)?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        addSubview(backgroundView)
        addSubview(camera)
        camera.isAccessibilityDecorative = true
        setAccessibilityLabel(strings().voiceOverCommonProfilePhoto)
        
        camera.image = theme.icons.profile_edit_photo
        camera.sizeToFit()
        camera.center()
        
        camera.isEventLess = true
        
        backgroundView.isEventLess = true
        
        set(handler: { [weak self] _ in
            if self?.updatingPhotoState == nil {
                self?.backgroundView.change(opacity: 0.8, animated: true)
                self?.camera.change(opacity: 0.8, animated: true)
            }
        }, for: .Highlight)
        
        set(handler: { [weak self] _ in
            if self?.updatingPhotoState == nil {
                self?.backgroundView.change(opacity: 1.0, animated: true)
                self?.camera.change(opacity: 1.0, animated: true)
            }
        }, for: .Normal)
        
        set(handler: { [weak self] _ in
            if self?.updatingPhotoState == nil {
                self?.backgroundView.change(opacity: 1.0, animated: true)
                self?.camera.change(opacity: 1.0, animated: true)
            }
        }, for: .Hover)
        
        backgroundView.backgroundColor = .blackTransparent
        backgroundView.frame = bounds
        
        if #available(macOS 10.15, *) {
            self.layer?.cornerCurve = .circular
        }
        
        set(handler: { [weak self] control in
            if self?.updatingPhotoState == nil {
                self?.setup?(nil, control)
            }
        }, for: .Click)
    }
    
    public func updateState(_ updatingPhotoState: PeerInfoUpdatingPhotoState?, animated: Bool) {
        self.updatingPhotoState = updatingPhotoState
        
        userInteractionEnabled = updatingPhotoState == nil
        
        self.camera.change(opacity: updatingPhotoState == nil ? 1.0 : 0.0, animated: true)
        
        if let uploadState = updatingPhotoState {
            if self.progressView == nil {
                self.progressView = RadialProgressContainerView(theme: RadialProgressTheme(backgroundColor: .clear, foregroundColor: .white, icon: nil))
                self.progressView!.frame = bounds
                progressView?.proggressBackground.backgroundColor = .clear
                self.addSubview(progressView!)
            }
            progressView?.progress.fetchControls = FetchControls(fetch: {
                updatingPhotoState?.cancel()
            })
            progressView?.progress.state = .Fetching(progress: uploadState.progress, force: false)
            
            if let _ = uploadState.image, self.tempImageView == nil {
                self.tempImageView = ImageView()
                self.tempImageView?.isAccessibilityDecorative = true
                self.tempImageView?.contentGravity = .resizeAspect
                self.tempImageView!.frame = bounds
                self.addSubview(tempImageView!, positioned: .below, relativeTo: backgroundView)
                if animated {
                    self.tempImageView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            self.tempImageView?.image = uploadState.image
        } else {
            if let progressView = self.progressView {
                self.progressView = nil
                if animated {
                    progressView.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak progressView] _ in
                        progressView?.removeFromSuperview()
                    })
                } else {
                    progressView.removeFromSuperview()
                }
            }
            if let tempImageView = self.tempImageView {
                self.tempImageView = nil
                if animated {
                    tempImageView.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak tempImageView] _ in
                        tempImageView?.removeFromSuperview()
                    })
                } else {
                    tempImageView.removeFromSuperview()
                }
            }
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
