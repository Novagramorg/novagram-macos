import Cocoa
import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramCallsCore


public final class GroupVideoView: LayerBackedView {
    
    
    private let videoViewContainer: LayerBackedView
    public let videoView: PresentationCallVideoView
    public var gravity: CALayerContentsGravity = .resizeAspect
    private var validLayout: CGSize?
    
    private var isMirrored: Bool = false {
        didSet {
            CATransaction.begin()
            if isMirrored {
                let rect = self.videoViewContainer.bounds
                var fr = CATransform3DIdentity
                fr = CATransform3DTranslate(fr, rect.width / 2, 0, 0)
                fr = CATransform3DScale(fr, -1, 1, 1)
                fr = CATransform3DTranslate(fr, -(rect.width / 2), 0, 0)
                self.videoViewContainer.layer?.sublayerTransform = fr
            } else {
                self.videoViewContainer.layer?.sublayerTransform = CATransform3DIdentity
            }
            CATransaction.commit()
        }
    }
    
    public var tapped: (() -> Void)?
    
    public init(videoView: PresentationCallVideoView) {
        self.videoViewContainer = LayerBackedView()
        self.videoView = videoView
        
        super.init()
        
        self.videoViewContainer.addSubview(self.videoView.view)
        self.addSubview(self.videoViewContainer)
        
        
        videoView.setOnOrientationUpdated({ [weak self] _, _ in
            guard let strongSelf = self else {
                return
            }
            if let size = strongSelf.validLayout {
                strongSelf.updateLayout(size: size, transition: .immediate)
            }
        })
        
        videoView.setOnIsMirroredUpdated({ [weak self] isMirrored in
            self?.isMirrored = isMirrored
        })
        
    }

    private let occlusionDisposable = MetaDisposable()
    private var isRenderingPaused = false

    deinit {
        occlusionDisposable.dispose()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window as? Window {
            occlusionDisposable.set((window.takeOcclusionState |> deliverOnMainQueue).start(next: { [weak self] state in
                self?.setRenderingPaused(!state.contains(.visible))
            }))
        } else {
            occlusionDisposable.set(nil)
            setRenderingPaused(false)
        }
    }

    private func setRenderingPaused(_ paused: Bool) {
        guard paused != isRenderingPaused else {
            return
        }
        isRenderingPaused = paused
        videoView.setIsPaused(paused)
    }
    
    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
    
    public override var mouseDownCanMoveWindow: Bool {
        return true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public func setVideoContentMode(_ contentMode: CALayerContentsGravity, animated: Bool) {
        self.gravity = contentMode
        self.validLayout = nil
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.3, curve: .easeOut) : .immediate
        self.updateLayout(size: frame.size, transition: transition)
    }
    
    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }
    public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        guard self.validLayout != size else {
            return
        }
        self.validLayout = size
        
        var videoRect: CGRect = .zero
        videoRect = focus(size)
        
        transition.updateFrame(view: self.videoViewContainer, frame: videoRect)
                

        transition.updateFrame(view: videoView.view, frame: videoRect)
        videoView.renderToSize(videoRect.size, transition.isAnimated)

        

        for subview in self.videoView.view.subviews {
            transition.updateFrame(view: subview, frame: videoRect.size.bounds)
        }
        
        var fr = CATransform3DIdentity
        if isMirrored {
            let rect = videoRect
            fr = CATransform3DTranslate(fr, rect.width / 2, 0, 0)
            fr = CATransform3DScale(fr, -1, 1, 1)
            fr = CATransform3DTranslate(fr, -(rect.width / 2), 0, 0)
        }
        
        switch transition {
        case .immediate:
            self.videoViewContainer.layer?.sublayerTransform = fr
        case let .animated(duration, curve):
            let animation = CABasicAnimation(keyPath: "sublayerTransform")
            animation.fromValue = self.videoViewContainer.layer?.presentation()?.sublayerTransform ?? self.videoViewContainer.layer?.sublayerTransform ?? CATransform3DIdentity
            animation.toValue = fr
            animation.timingFunction = .init(name: curve.timingFunction)
            animation.duration = duration
            self.videoViewContainer.layer?.add(animation, forKey: "sublayerTransform")
            self.videoViewContainer.layer?.sublayerTransform = fr
        }

    }
    
    public override func viewDidMoveToSuperview() {
        if superview == nil {
            didRemoveFromSuperview?()
        } 
    }
    
    public var didRemoveFromSuperview: (()->Void)? = nil
}
