#if SHARE
import TelegramUtilsShare
#else
import TelegramUtils
#endif

#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif
import Cocoa
import TelegramCore

import Postbox
import TGUIKit
import SwiftSignalKit


public enum AvatarNodeState: Equatable {
    case Empty
    case PeerAvatar(Peer, [String], TelegramMediaImageRepresentation?, PeerNameColor?, Message?, NSSize?, Bool, CGFloat?)
    case ArchivedChats
}

public func ==(lhs: AvatarNodeState, rhs: AvatarNodeState) -> Bool {
    switch (lhs, rhs) {
    case (.Empty, .Empty):
        return true
    case let (.PeerAvatar(lhsPeer, lhsLetters, lhsPhotoRepresentations, lhsPeerNameColor, _, lhsSize, lhsForum, lhsCornerRadius), .PeerAvatar(rhsPeer, rhsLetters, rhsPhotoRepresentations, rhsPeerNameColor, _, rhsSize, rhsForum, rhsCornerRadius)):
        return lhsPeer.isEqual(rhsPeer) && lhsLetters == rhsLetters && lhsPhotoRepresentations == rhsPhotoRepresentations && lhsSize == rhsSize && lhsForum == rhsForum && lhsPeerNameColor == rhsPeerNameColor && lhsCornerRadius == rhsCornerRadius
    case (.ArchivedChats, .ArchivedChats):
        return true
    default:
        return false
    }
}

open class AvatarControl: NSView {
    private var trackingArea:NSTrackingArea?
    private var displaySuspended:Bool = false
    open var userInteractionEnabled:Bool = true
    private let longOverHandleDisposable = MetaDisposable()

    private var handlers:[(ControlEvent,(AvatarControl) -> Void)] = []

    open var font: NSFont {
        didSet {
            if oldValue !== font {

                if !self.displaySuspended {
                    self.needsDisplay = true
                }
            }
        }
    }



    private let disposable = MetaDisposable()

    private var state: AvatarNodeState = .Empty
    private var account:Account?
    private var disableForum: Bool = false
    private var forceCommunityStyle: Bool = false
    private var contentScale: CGFloat = 0

    // Community peers show a decorative "stack" behind the (full-size, forum-rounded) avatar — two faded
    // cards peeking out behind-left. The avatar normally lives in `layer.contents`, which always draws
    // BEHIND sublayers, so for community we route the avatar into a content sublayer and place the stack
    // sublayer below it (and disable clipping so the stack can peek beyond the bounds).
    private var communityStack = false
    private var communityStackLayer: SimpleLayer?
    private var communityContentLayer: SimpleLayer?

    /// The stack asset's front-card rect, as fractions of the image — derived once from the asset's alpha
    /// (the densest, frontmost card band). The avatar maps exactly onto this rect; the faded back cards
    /// then occupy the surrounding margins. Pixel-derived, so it stays correct if the asset is redrawn.
    private static let communityStackFrontCard: CGRect = {
        let fallback = CGRect(x: 1.0 / 6.0, y: 1.0 / 6.0, width: 2.0 / 3.0, height: 2.0 / 3.0)
        guard let rep = NSImage(named: "Icon_Community_AvatarStack")?.tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0) }) else {
            return fallback
        }
        let w = rep.pixelsWide, h = rep.pixelsHigh
        guard w > 1, h > 1 else { return fallback }
        var maxAlpha: CGFloat = 0
        for y in stride(from: 0, to: h, by: 2) {
            for x in stride(from: 0, to: w, by: 2) {
                maxAlpha = max(maxAlpha, rep.colorAt(x: x, y: y)?.alphaComponent ?? 0)
            }
        }
        guard maxAlpha > 0 else { return fallback }
        let threshold = maxAlpha * 0.9
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in stride(from: 0, to: h, by: 2) {
            for x in stride(from: 0, to: w, by: 2) {
                if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) >= threshold {
                    minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return fallback }
        return CGRect(x: CGFloat(minX) / CGFloat(w), y: CGFloat(minY) / CGFloat(h),
                      width: CGFloat(maxX - minX) / CGFloat(w), height: CGFloat(maxY - minY) / CGFloat(h))
    }()

    open var contentUpdated: ((Any?)->Void)?

    open func callContentUpdater() {
        self.contentUpdated?(self.imageContents)
    }

    open var imageContents: Any? {
        didSet {
            if communityStack {
                communityContentLayer?.contents = imageContents
            } else {
                self.layer?.contents = imageContents
            }
            self.contentUpdated?(imageContents)
            noteImageDisplayed()
        }
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        noteImageDisplayed()
    }

    private func noteImageDisplayed() {
        if window != nil, let contents = imageContents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
            ScopedImageCache.noteDisplayed(contents as! CGImage, in: self)
        }
    }

    /// Toggle the community avatar-stack decoration. When enabled the avatar moves into a content sublayer
    /// (full-size, on top) and the stack image is drawn behind it, peeking beyond the bounds.
    private func setCommunityStack(_ enabled: Bool) {
        guard enabled != communityStack else { return }
        communityStack = enabled
        if enabled {
            self.layer?.masksToBounds = false
            let stack = SimpleLayer()
            stack.contentsGravity = .resize
            stack.contentsScale = backingScaleFactor
            stack.contents = NSImage(named: "Icon_Community_AvatarStack")?.precomposed()
            self.layer?.addSublayer(stack)
            communityStackLayer = stack

            let content = SimpleLayer()
            content.contentsGravity = .resize
            content.contentsScale = backingScaleFactor
            content.contents = self.layer?.contents   // carry the current avatar over
            self.layer?.addSublayer(content)
            communityContentLayer = content

            self.layer?.contents = nil
            layoutCommunityLayers()
        } else {
            self.layer?.contents = communityContentLayer?.contents
            communityStackLayer?.removeFromSuperlayer(); communityStackLayer = nil
            communityContentLayer?.removeFromSuperlayer(); communityContentLayer = nil
        }
    }

    private func layoutCommunityLayers() {
        guard communityStack else { return }
        let b = self.bounds
        communityContentLayer?.frame = b
        // Scale the stack so its (pixel-detected) centred front card covers the avatar bounds; the faded
        // back cards then peek out around it. No hand-tuned magic numbers — the rect comes from the asset.
        let card = AvatarControl.communityStackFrontCard
        let stackW = card.width > 0 ? b.width / card.width : b.width
        let stackH = card.height > 0 ? b.height / card.height : b.height
        communityStackLayer?.frame = CGRect(x: b.midX - stackW / 2, y: b.midY - stackH / 2, width: stackW, height: stackH)
    }

    open var animated: Bool = false
    private var _attemptLoadNextSynchronous: Bool = false
    open var attemptLoadNextSynchronous: Bool {
        get {
            let result = _attemptLoadNextSynchronous
            _attemptLoadNextSynchronous = false
            return result
        }
        set {
            _attemptLoadNextSynchronous = newValue
        }
    }

    public init(font: NSFont) {
        self.font = font
        super.init(frame: NSZeroRect)
        wantsLayer = true
    }


    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required override init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    open override var frame: CGRect {
        get {
            return super.frame
        } set(value) {
            let updateImage = !value.size.equalTo(super.frame.size)
            super.frame = value
            if updateImage {
                layoutCommunityLayers()
            }
            if updateImage && !self.displaySuspended {
                self.needsDisplay = true
            }
        }
    }

    open func setState(account: Account, state: AvatarNodeState) {
        self.account = account
        if case let .PeerAvatar(peer, _, _, _, _, _, _, _) = state {
            setCommunityStack((peer is TelegramCommunity) && !disableForum)
        } else {
            setCommunityStack(false)
        }
        if state != self.state {
            contentScale = 0
            self.state = state
            self.viewDidChangeBackingProperties()
        }
    }

    open func setPeer(account: Account, peer: Peer?, message: Message? = nil, size: NSSize? = nil, disableForum: Bool = false, cornerRadius: CGFloat? = nil, forceMonoforum: Bool = false, forceCommunity: Bool = false) {
        self.account = account
        self.disableForum = disableForum
        self.forceCommunityStyle = forceCommunity
        let state: AvatarNodeState
        if let peer = peer {
            state = .PeerAvatar(peer, TelegramUtilsHooks.shared.peerLetters(peer), peer.smallProfileImage, peer.namePeerColor, message, size, ((peer.isForumOrMonoForum || (peer is TelegramCommunity)) && !disableForum) || forceMonoforum || forceCommunity, cornerRadius)
            setCommunityStack(((peer is TelegramCommunity) || forceCommunity) && !disableForum)
        } else {
            state = .Empty
            setCommunityStack(false)
        }
        if self.state != state || self.imageContents == nil {
            self.state = state
            contentScale = 0
            self.viewDidChangeBackingProperties()
        }
    }

    open func set(handler:@escaping (AvatarControl) -> Void, for event:ControlEvent) -> Void {
        handlers.append((event,handler))
    }

    override open func mouseEntered(with event: NSEvent) {
        if userInteractionEnabled {

            let disposable = (Signal<Void,Void>.single(Void()) |> delay(0.3, queue: Queue.mainQueue())).start(next: { [weak self] in
                if let strongSelf = self, strongSelf._mouseInside() {
                    strongSelf.send(event: .LongOver)
                }
            })
            longOverHandleDisposable.set(disposable)

        } else {
            super.mouseEntered(with: event)
        }
    }

    open override func mouseDown(with event: NSEvent) {
        if userInteractionEnabled {
            longOverHandleDisposable.set(nil)
        } else {
            super.mouseDown(with: event)
        }
    }

    override open func mouseUp(with event: NSEvent) {

        if userInteractionEnabled {

            if _mouseInside() {
                if event.clickCount == 1  {
                    send(event: .SingleClick)
                }
                send(event: .Click)
            }

        } else {
            super.mouseUp(with: event)
        }
    }

    open func removeAllHandlers() ->Void {
        handlers.removeAll()
    }

    open func send(event:ControlEvent) -> Void {
        for (e,handler) in handlers {
            if e == event {
                handler(self)
            }
        }
    }

    open override func viewDidChangeBackingProperties() {

        layer?.contentsScale = backingScaleFactor
        layer?.contentsGravity = .resizeAspectFill

        if let account = account, self.state != .Empty {
            if contentScale != backingScaleFactor {
                contentScale = backingScaleFactor
                self.displaySuspended = true
                self.imageContents = nil
                let photo: PeerPhoto?
                var updatedSize: NSSize = self.frame.size

                let _disableForum: Bool

                switch state {
                case let .PeerAvatar(peer, letters, representation, nameColor, message, size, isForum, cornerRadius):
                    _disableForum = !isForum
                    if let peer = peer as? TelegramUser, peer.firstName == nil && peer.lastName == nil {
                        photo = nil
                        self.setState(account: account, state: .Empty)
                        let icon = theme.icons.deletedAccount
                        self.setSignal(generateEmptyPhoto(updatedSize, type: .icon(colors: theme.colors.peerColors(Int(peer.id.id._internalGetInt64Value() % 7)), icon: icon, iconSize: icon.backingSize.aspectFitted(NSMakeSize(min(50, updatedSize.width - 20), min(updatedSize.height - 20, 50))), cornerRadius: nil), bubble: peer.isMonoForum) |> map {($0, false)})
                        return
                    } else {
                        photo = .peer(peer, representation, nameColor, letters, message, cornerRadius)
                    }
                    updatedSize = size ?? frame.size
                case .Empty:
                    photo = nil
                    _disableForum = disableForum
                default:
                    photo = nil
                    _disableForum = disableForum
                }
                if let photo = photo {
                    setSignal(peerAvatarImage(account: account, photo: photo, displayDimensions: updatedSize, scale:backingScaleFactor, font: self.font, synchronousLoad: attemptLoadNextSynchronous, disableForum: _disableForum, forceForum: self.forceCommunityStyle), force: false)
                } else {
                    let content = self.imageContents
                    self.displaySuspended = false
                    self.imageContents = content
                }

            }
        } else {
            self.state = .Empty
        }
    }

    open func setSignal(_ signal: Signal<(CGImage?, Bool), NoError>, force: Bool = true) {
        if force {
            self.state = .Empty
            // A forced external image (Saved Messages, custom icons) is never a community — drop any
            // stack decoration left over from a recycled community avatar. The community generation
            // path uses force: false, so its stack is preserved.
            setCommunityStack(false)
        }
        self.disposable.set((signal |> deliverOnMainQueue).start(next: { [weak self] image, animated in
            if let strongSelf = self {
                strongSelf.imageContents = image
                if animated {
                    strongSelf.layer?.animateContents()
                }
            }
        }))
    }

    open override func updateTrackingAreas() {
        super.updateTrackingAreas();


        if let trackingArea = trackingArea {
            self.removeTrackingArea(trackingArea)
        }

        trackingArea = nil

        if let _ = window {
            let options:NSTrackingArea.Options = [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect]
            self.trackingArea = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)

            self.addTrackingArea(self.trackingArea!)
        }
    }

    open override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateTrackingAreas()
    }

    deinit {
        if let trackingArea = self.trackingArea {
            self.removeTrackingArea(trackingArea)
        }
        disposable.dispose()
        longOverHandleDisposable.dispose()
    }

    open override func copy() -> Any {
        let view = NSView()
        view.wantsLayer = true
        view.background = .clear
        view.layer?.frame = NSMakeRect(0, visibleRect.minY == 0 ? 0 : visibleRect.height - frame.height, frame.width,  frame.height)
        view.layer?.contents = self.imageContents
        view.layer?.masksToBounds = true
        view.frame = self.visibleRect
        view.layer?.shouldRasterize = true
        view.layer?.rasterizationScale = backingScaleFactor
        return view
    }
}
