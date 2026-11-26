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

protocol AvatarImageRenderHost: AnyObject {
    var avatarHostLayer: CALayer? { get }
    var avatarHostSize: NSSize { get }
    var avatarHostBounds: NSRect { get }
    var avatarBackingScale: CGFloat { get }
    var avatarFont: NSFont { get }
    var avatarDisplayView: NSView? { get }
    func avatarContentsDidUpdate(_ contents: Any?)
}

final class AvatarImageRenderer {
    private weak var host: AvatarImageRenderHost?
    private let disposable: MetaDisposable

    private(set) var displaySuspended: Bool = false
    private var state: AvatarNodeState = .Empty
    private var account: Account?
    private var disableForum: Bool = false
    private var forceCommunityStyle: Bool = false
    private var contentScale: CGFloat = 0

    private var communityStack = false
    private var communityStackLayer: SimpleLayer?
    private var communityContentLayer: SimpleLayer?

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

    init(host: AvatarImageRenderHost, disposable: MetaDisposable) {
        self.host = host
        self.disposable = disposable
    }

    var imageContents: Any? {
        didSet {
            if communityStack {
                communityContentLayer?.contents = imageContents
            } else {
                host?.avatarHostLayer?.contents = imageContents
            }
            host?.avatarContentsDidUpdate(imageContents)
            noteImageDisplayed()
        }
    }

    func noteImageDisplayed() {
        if let view = host?.avatarDisplayView, view.window != nil, let contents = imageContents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID {
            ScopedImageCache.noteDisplayed(contents as! CGImage, in: view)
        }
    }

    private func setCommunityStack(_ enabled: Bool) {
        guard enabled != communityStack, let host else { return }
        communityStack = enabled
        let layer = host.avatarHostLayer
        if enabled {
            layer?.masksToBounds = false
            let stack = SimpleLayer()
            stack.contentsGravity = .resize
            stack.contentsScale = host.avatarBackingScale
            stack.contents = NSImage(named: "Icon_Community_AvatarStack")?.precomposed()
            layer?.addSublayer(stack)
            communityStackLayer = stack

            let content = SimpleLayer()
            content.contentsGravity = .resize
            content.contentsScale = host.avatarBackingScale
            content.contents = layer?.contents
            layer?.addSublayer(content)
            communityContentLayer = content

            layer?.contents = nil
            layoutCommunityLayers()
        } else {
            layer?.contents = communityContentLayer?.contents
            communityStackLayer?.removeFromSuperlayer(); communityStackLayer = nil
            communityContentLayer?.removeFromSuperlayer(); communityContentLayer = nil
        }
    }

    func layoutCommunityLayers() {
        guard communityStack, let host else { return }
        let b = host.avatarHostBounds
        communityContentLayer?.frame = b
        let card = AvatarImageRenderer.communityStackFrontCard
        let stackW = card.width > 0 ? b.width / card.width : b.width
        let stackH = card.height > 0 ? b.height / card.height : b.height
        communityStackLayer?.frame = CGRect(x: b.midX - stackW / 2, y: b.midY - stackH / 2, width: stackW, height: stackH)
    }

    private var _attemptLoadNextSynchronous: Bool = false
    var attemptLoadNextSynchronous: Bool {
        get {
            let result = _attemptLoadNextSynchronous
            _attemptLoadNextSynchronous = false
            return result
        }
        set {
            _attemptLoadNextSynchronous = newValue
        }
    }

    func setState(account: Account, state: AvatarNodeState) {
        self.account = account
        if case let .PeerAvatar(peer, _, _, _, _, _, _, _) = state {
            setCommunityStack((peer is TelegramCommunity) && !disableForum)
        } else {
            setCommunityStack(false)
        }
        if state != self.state {
            contentScale = 0
            self.state = state
            self.updateBacking()
        }
    }

    func setPeer(account: Account, peer: Peer?, message: Message? = nil, size: NSSize? = nil, disableForum: Bool = false, cornerRadius: CGFloat? = nil, forceMonoforum: Bool = false, forceCommunity: Bool = false) {
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
            self.updateBacking()
        }
    }

    func updateBacking() {
        guard let host else { return }
        let backingScaleFactor = host.avatarBackingScale
        host.avatarHostLayer?.contentsScale = backingScaleFactor
        host.avatarHostLayer?.contentsGravity = .resizeAspectFill

        if let account = account, self.state != .Empty {
            if contentScale != backingScaleFactor {
                contentScale = backingScaleFactor
                self.displaySuspended = true
                self.imageContents = nil
                let photo: PeerPhoto?
                var updatedSize: NSSize = host.avatarHostSize

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
                    updatedSize = size ?? host.avatarHostSize
                case .Empty:
                    photo = nil
                    _disableForum = disableForum
                default:
                    photo = nil
                    _disableForum = disableForum
                }
                if let photo = photo {
                    setSignal(peerAvatarImage(account: account, photo: photo, displayDimensions: updatedSize, scale: backingScaleFactor, font: host.avatarFont, synchronousLoad: attemptLoadNextSynchronous, disableForum: _disableForum, forceForum: self.forceCommunityStyle), force: false)
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

    func setSignal(_ signal: Signal<(CGImage?, Bool), NoError>, force: Bool = true) {
        if force {
            self.state = .Empty
            setCommunityStack(false)
        }
        self.disposable.set((signal |> deliverOnMainQueue).start(next: { [weak self] image, animated in
            if let strongSelf = self {
                strongSelf.imageContents = image
                if animated {
                    strongSelf.host?.avatarHostLayer?.animateContents()
                }
            }
        }))
    }
}

open class AvatarControl: NSView, AvatarImageRenderHost {
    private var trackingArea:NSTrackingArea?
    open var userInteractionEnabled:Bool = true
    private let longOverHandleDisposable = MetaDisposable()

    private var handlers:[(ControlEvent,(AvatarControl) -> Void)] = []

    open var font: NSFont {
        didSet {
            if oldValue !== font {

                if !renderer.displaySuspended {
                    self.needsDisplay = true
                }
            }
        }
    }

    private let disposable = MetaDisposable()
    private lazy var renderer = AvatarImageRenderer(host: self, disposable: disposable)

    var avatarHostLayer: CALayer? { layer }
    var avatarHostSize: NSSize { frame.size }
    var avatarHostBounds: NSRect { bounds }
    var avatarBackingScale: CGFloat { backingScaleFactor }
    var avatarFont: NSFont { font }
    var avatarDisplayView: NSView? { self }
    func avatarContentsDidUpdate(_ contents: Any?) {
        self.contentUpdated?(contents)
    }

    open var contentUpdated: ((Any?)->Void)?

    open func callContentUpdater() {
        self.contentUpdated?(self.imageContents)
    }

    open var imageContents: Any? {
        get {
            return renderer.imageContents
        }
        set {
            renderer.imageContents = newValue
        }
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        noteImageDisplayed()
        updateTrackingAreas()
    }

    private func noteImageDisplayed() {
        renderer.noteImageDisplayed()
    }

    open var animated: Bool = false
    open var attemptLoadNextSynchronous: Bool {
        get {
            return renderer.attemptLoadNextSynchronous
        }
        set {
            renderer.attemptLoadNextSynchronous = newValue
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
                renderer.layoutCommunityLayers()
            }
            if updateImage && !renderer.displaySuspended {
                self.needsDisplay = true
            }
        }
    }

    open func setState(account: Account, state: AvatarNodeState) {
        renderer.setState(account: account, state: state)
    }

    open func setPeer(account: Account, peer: Peer?, message: Message? = nil, size: NSSize? = nil, disableForum: Bool = false, cornerRadius: CGFloat? = nil, forceMonoforum: Bool = false, forceCommunity: Bool = false) {
        renderer.setPeer(account: account, peer: peer, message: message, size: size, disableForum: disableForum, cornerRadius: cornerRadius, forceMonoforum: forceMonoforum, forceCommunity: forceCommunity)
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
        renderer.updateBacking()
    }

    open func setSignal(_ signal: Signal<(CGImage?, Bool), NoError>, force: Bool = true) {
        renderer.setSignal(signal, force: force)
    }

    open override func updateTrackingAreas() {
        super.updateTrackingAreas();

        let needsTracking = window != nil
        if needsTracking == (trackingArea != nil) {
            return
        }

        if let trackingArea = trackingArea {
            self.removeTrackingArea(trackingArea)
        }

        trackingArea = nil

        if needsTracking {
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

public final class AvatarImageLayer: SimpleLayer, AvatarImageRenderHost {
    private let disposable = MetaDisposable()
    private lazy var renderer = AvatarImageRenderer(host: self, disposable: disposable)

    public var font: NSFont
    public var contentUpdated: ((Any?) -> Void)?
    public weak var displayView: NSView? {
        didSet {
            if displayView !== oldValue {
                renderer.noteImageDisplayed()
            }
        }
    }

    public init(font: NSFont) {
        self.font = font
        super.init()
    }

    public override init(layer: Any) {
        self.font = (layer as? AvatarImageLayer)?.font ?? .systemFont(ofSize: 13)
        super.init(layer: layer)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        disposable.dispose()
    }

    var avatarHostLayer: CALayer? { self }
    var avatarHostSize: NSSize { bounds.size }
    var avatarHostBounds: NSRect { bounds }
    var avatarBackingScale: CGFloat { contentsScale }
    var avatarFont: NSFont { font }
    var avatarDisplayView: NSView? { displayView }
    func avatarContentsDidUpdate(_ contents: Any?) {
        contentUpdated?(contents)
    }

    public var imageContents: Any? {
        return renderer.imageContents
    }

    public var attemptLoadNextSynchronous: Bool {
        get { renderer.attemptLoadNextSynchronous }
        set { renderer.attemptLoadNextSynchronous = newValue }
    }

    public func setPeer(account: Account, peer: Peer?, message: Message? = nil, size: NSSize? = nil, disableForum: Bool = false, cornerRadius: CGFloat? = nil, forceMonoforum: Bool = false, forceCommunity: Bool = false) {
        renderer.setPeer(account: account, peer: peer, message: message, size: size, disableForum: disableForum, cornerRadius: cornerRadius, forceMonoforum: forceMonoforum, forceCommunity: forceCommunity)
    }

    public func setState(account: Account, state: AvatarNodeState) {
        renderer.setState(account: account, state: state)
    }

    public func setSignal(_ signal: Signal<(CGImage?, Bool), NoError>, force: Bool = true) {
        renderer.setSignal(signal, force: force)
    }

    public func updateScale(_ scale: CGFloat) {
        if contentsScale != scale {
            contentsScale = scale
            renderer.updateBacking()
        }
    }

    public func layoutContent() {
        renderer.layoutCommunityLayers()
    }

    public func hostDidMoveToWindow() {
        renderer.noteImageDisplayed()
    }
}
