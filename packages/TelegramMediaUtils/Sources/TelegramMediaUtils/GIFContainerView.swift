import Cocoa
import TelegramCore

import TGUIKit
import TelegramContext
import TelegramTheme
import InAppSettings
import Postbox
import SwiftSignalKit
import TelegramMediaResources



public class GIFContainerView: Control {

    public let player:GifPlayerBufferView = GifPlayerBufferView()
    
    
    private var progressView:RadialProgressView?
    private let statusDisposable = MetaDisposable()
    private let fetchDisposable = MetaDisposable()
    private let playerDisposable = MetaDisposable()
    
    private var context: (any AccountContextProtocol)?
    private var size:NSSize = NSZeroSize
    private var ignoreWindowKey: Bool = false
    private weak var tableView:TableView?
    
    public var associatedMessageId: MessageId? = nil
    private var fileReference: FileMediaReference?


    public override init() {
        
        
        super.init()
        addSubview(player)
        self.backgroundColor = .clear
        
        

        player.background = .clear
        player.setVideoLayerGravity(.resizeAspectFill)
        set(handler: { [weak self] control in
            if let `self` = self, let window = self.window as? Window, let table = self.tableView, let context = self.context {
                MediaRenderHooks.shared.startModalPreview(table, window, context)
            }
        }, for: .LongMouseDown)
        
    }
    
    
    public required convenience init(frame frameRect: NSRect) {
        self.init()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func clean() {
        fetchDisposable.dispose()
        statusDisposable.dispose()
        playerDisposable.dispose()
        removeNotificationListeners()
    }
    
    public func cancel() {
        fetchDisposable.set(nil)
        statusDisposable.set(nil)
    }
    
    
    public func cancelFetching() {
        if let reference = fileReference {
            context?.account.postbox.mediaBox.cancelInteractiveResourceFetch(reference.media.resource)
        }
    }
    
    
    public func fetch() {
        if let context = context, let reference = fileReference {
            fetchDisposable.set(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: reference.userLocation, userContentType: reference.userContentType, reference: reference.resourceReference(reference.media.resource), statsCategory: .file).start())
        }
    }
    
    public func removeNotificationListeners() {
        NotificationCenter.default.removeObserver(self)
    }
    
    
    public var accept: Bool {
        let wAccept = window != nil && (window!.isKeyWindow || self.ignoreWindowKey)  && !NSIsEmptyRect(visibleRect)
        var accept:Bool = wAccept
        if let context = self.context, context.isLite(.gif) && tableView != nil {
            accept = accept && mouseInside()
        }
        return accept
    }
    
    
    @objc public func updatePlayerIfNeeded() {
        
        let accept = self.accept
        
        if !ignoreWindowKey {
            if accept && self.player.ticking {
                return
            }
            var s:Signal<Void, Void> = .single(Void())
            if accept {
                s = s |> delay(0.05, queue: Queue.mainQueue())
            }
            playerDisposable.set(s.start(next: {[weak self] (next) in
                if let strongSelf = self {
                    strongSelf.player.ticking = accept
                }
            }))
        } else {
            playerDisposable.set(nil)
            self.player.ticking = accept
        }
        
    }
    
    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        self.updatePlayerIfNeeded()
    }
    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        self.updatePlayerIfNeeded()
    }
    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        self.updatePlayerIfNeeded()
    }
    
    
    public func updateListeners() {
        removeNotificationListeners()

        if let window = window {
            NotificationCenter.default.addObserver(self, selector: #selector(updatePlayerIfNeeded), name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(updatePlayerIfNeeded), name: NSWindow.didResignKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(updatePlayerIfNeeded), name: NSView.boundsDidChangeNotification, object: tableView?.clipView)
            NotificationCenter.default.addObserver(self, selector: #selector(updatePlayerIfNeeded), name: NSView.frameDidChangeNotification, object: tableView?.view)
        }
    }
    deinit {
        playerDisposable.dispose()
        removeNotificationListeners()
        clean()
    }
    
    public override func viewDidMoveToWindow() {
        updateListeners()
        updatePlayerIfNeeded()
    }
    
    
    public func update(with fileReference: FileMediaReference, size: NSSize, viewSize:NSSize, context: (any AccountContextProtocol), table: TableView?, ignoreWindowKey: Bool = false, isPreview: Bool = true) {
        
        
        let updated = self.fileReference == nil || !fileReference.media.isEqual(to: self.fileReference!.media)
        
        self.tableView = table
        self.fileReference = fileReference
        self.context = context
        self.size = size
        self.setFrameSize(size)
        self.ignoreWindowKey = ignoreWindowKey
        self.layer?.borderColor = theme.colors.background.cgColor
        
        player.setFrameSize(viewSize)
        player.center()
        progressView?.center()
        
        
        
        let imageSize = viewSize.aspectFitted(NSMakeSize(size.width, size.height))
        let size = (fileReference.media.dimensions?.size ?? imageSize).aspectFilled(viewSize)
        let arguments = TransformImageArguments(corners: ImageCorners(radius:0), imageSize: size, boundingSize: imageSize, intrinsicInsets: NSEdgeInsets())
        
        player.set(arguments: arguments)
        
        
        player.setSignal(signal: cachedMedia(media: fileReference.media, arguments: arguments, scale: backingScaleFactor), clearInstantly: updated)

        
        if isPreview {
            let signal = chatMessageVideo(account: context.account, fileReference: fileReference, scale: backingScaleFactor, autoFetchFullSize: true)

            if !player.isFullyLoaded {
                player.setSignal(signal, cacheImage: { result in
                    cacheMedia(result, media: fileReference.media, arguments: arguments, scale: System.backingScale)
                })
            }
        } else {
            player.clear()
        }
        
        player.update(fileReference, context: context)

        updatePlayerIfNeeded()
        
        fetch()
        
        needsLayout = true
    }
    

    
    public override func layout() {
        super.layout()
        progressView?.center()
        updatePlayerIfNeeded()
    }
    
    public override func copy() -> Any {
        let view = View()
        view.backgroundColor = .clear
        let layer:CALayer = CALayer()
        layer.frame = NSMakeRect(0, visibleRect.minY == 0 ? 0 :  player.visibleRect.height - player.frame.height, player.frame.width,  player.frame.height)
        layer.contents = player.layer?.contents ?? player.imageHolder
        layer.masksToBounds = true
        view.frame = player.visibleRect
        layer.shouldRasterize = true
        layer.rasterizationScale = backingScaleFactor
        view.layer?.addSublayer(layer)
        return view
    }

    
}
