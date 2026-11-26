import CoreMedia
import Cocoa
import TGUIKit
import TelegramCore
import TelegramMedia
import Postbox
import SwiftSignalKit
import AudioPlayerCore
import ChatModeTypes
import TelegramContext
import TelegramMediaUtils
import TelegramTheme

enum InstantVideoPIPCornerAlignment {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

public class InstantVideoPIPView : GIFPlayerView {
    let playingProgressView: RadialProgressView = RadialProgressView(theme:RadialProgressTheme(backgroundColor: .clear, foregroundColor: NSColor.white.withAlphaComponent(0.8), lineWidth: 3), twist: false)

    public override init() {
        super.init()
    }
    
    public required init(frame frameRect: NSRect) {
        super.init()
        setFrameSize(NSMakeSize(200, 200))
        playingProgressView.userInteractionEnabled = false
    }
    
    public override func viewDidMoveToWindow() {
        if let _ = window {
            playingProgressView.frame = bounds
            addSubview(playingProgressView)
        } else {
            playingProgressView.removeFromSuperview()
        }
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

public class InstantVideoPIP: GenericViewController<InstantVideoPIPView>, APDelegate {
    private var controller:APController
    private var context: any AccountContextProtocol
    private weak var tableView:TableView?
    private var listener:TableScrollListener!
    private var navigationListener: WeakReference<ViewController>!
    
    private let dataDisposable = MetaDisposable()
    private let fetchDisposable = MetaDisposable()
    
    private var currentMessage:Message? = nil
    private var scrollTime: TimeInterval = CFAbsoluteTimeGetCurrent()
    private var alignment:InstantVideoPIPCornerAlignment = .topRight
    private var isShown:Bool = false
    private var __window: Window
    private var presentationGeneration: UInt64 = 0
    private var displayedMessageId: MessageId?
    private var displayedResourceId: MediaResourceId?
    
    private var timebase: CMTimebase? = nil {
        didSet {
            if isLoaded(), oldValue !== timebase {
                genericView.reset(with: timebase)
            }
        }
    }
    
    public init(_ controller:APController, context: any AccountContextProtocol, window:Window) {
        self.controller = controller
        self.context = context
        self.__window = window
        super.init()
        listener = TableScrollListener({ [weak self] _ in
            self?.updateScrolled()
        })
        controller.add(listener: self)
        navigationListener = WeakReference(value: self)
        context.bindings.rootNavigation().add(listener: navigationListener)
    }
    
    public override var window:Window? {
        return __window
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.layer?.borderColor = NSColor.clear.cgColor
        view.layer?.borderWidth = 0
        view.autoresizingMask = [.maxYMargin, .minXMargin]
    }
    
    public override func navigationWillChangeController() {
        if let controller = context.bindings.rootNavigation().controller as? ChatControllerKind {
            updateTableView(controller.genericView.tableView, context: context, controller: self.controller)
        } else {
            updateTableView(nil, context: context, controller: self.controller)
        }
    }
    
    
    private func updateScrolled() {
        
        scrollTime = CFAbsoluteTimeGetCurrent()
        let isAnimateScrolling = tableView?.clipView.isAnimateScrolling ?? false
        if !isAnimateScrolling {
            if let currentMessage = currentMessage {
                var needShow:Bool = true
                tableView?.enumerateVisibleViews(with: { view in
                    if let view = view as? ChatRowView, let item = view.item as? ChatRowItem {
                        if let stableId = item.stableId.base as? ChatHistoryEntryId {
                            if case .message(let message) = stableId {
                                if message.id == currentMessage.id, view.visibleRect.size == view.frame.size {
                                    if let state = item.entry.additionalData.transribeState {
                                        loop: switch state {
                                        case .collapsed:
                                            needShow = false
                                        default:
                                            break loop
                                        }
                                    } else {
                                        needShow = false
                                    }
                                }
                            }
                        }
                    }
                })
                if needShow {
                    showIfNeeded(animated: !isShown)
                } else {
                    if isShown {
                        hide()
                    }
                }
            } else {
                hide()
            }
        }
    }
    
    deinit {
        tableView?.removeScroll(listener: listener)
        controller.remove(listener: self)
        context.bindings.rootNavigation().remove(listener: navigationListener)
        window?.removeAllHandlers(for: self)
        if isLoaded() {
            genericView.set(data: nil)
            genericView.clear()
            genericView.removeFromSuperview()
        }
        dataDisposable.dispose()
        fetchDisposable.dispose()
    }
    
    func showIfNeeded(animated: Bool = true) {
        guard let message = currentMessage, let media = message.anyMedia as? TelegramMediaFile, window?.contentView != nil else {
            return
        }
        loadViewIfNeeded()
        let wasShown = isShown
        isShown = true
        genericView.animatesAlphaOnFirstTransition = false
        if !wasShown || displayedMessageId != message.id || displayedResourceId != media.resource.id {
            presentationGeneration &+= 1
            displayedMessageId = message.id
            displayedResourceId = media.resource.id
            let generation = presentationGeneration
            genericView.set(data: nil)
            let signal:Signal<ImageDataTransformation, NoError> = chatMessageVideo(account: context.account, fileReference: FileMediaReference.message(message: MessageReference(message), media: media), scale: view.backingScaleFactor)
            
            let resource = FileMediaReference.message(message: MessageReference(message), media: media)
            
            let data: Signal<AVGifData?, NoError> = context.account.postbox.mediaBox.resourceData(resource.media.resource) |> map { resource in
                if resource.complete {
                    return AVGifData.dataFrom(resource.path)
                } else if let resource = media.resource as? LocalFileReferenceMediaResource {
                    return AVGifData.dataFrom(resource.localFilePath)
                } else {
                    return nil
                }
            } |> deliverOnMainQueue
            
            genericView.setSignal(signal)
            
            dataDisposable.set(data.start(next: { [weak self] data in
                guard let self, self.isShown, self.presentationGeneration == generation else {
                    return
                }
                self.genericView.set(data: data, timebase: self.timebase)
            }))
            
        }

        if let contentView = window?.contentView, genericView.superview == nil {
            contentView.addSubview(genericView)
            genericView.layer?.cornerRadius = view.frame.width/2
            
         
            if genericView.frame.minX == 0 {
                if let contentView = window?.contentView {
                    switch alignment {
                    case .topRight:
                        genericView.setFrameOrigin(NSMakePoint(contentView.frame.width, contentView.frame.height - view.frame.height - 130))
                    case .topLeft:
                        genericView.setFrameOrigin(NSMakePoint(-genericView.frame.width, contentView.frame.height - view.frame.height - 130))
                    case .bottomRight:
                        genericView.setFrameOrigin(NSMakePoint(contentView.frame.width, 100))
                    case .bottomLeft:
                        genericView.setFrameOrigin(NSMakePoint(-genericView.frame.width, 100))
                    }
                }
            }

        }
        if !wasShown {
            alignToCorner(alignment, animated)
        }
        guard !wasShown else {
            return
        }
        
        var startDragPosition:NSPoint? = nil
        var startViewPosition:NSPoint = view.frame.origin
        window?.set(mouseHandler: { [weak self] (_) -> KeyHandlerResult in
            if let strongSelf = self, let _ = startDragPosition {
                if startViewPosition.x == strongSelf.view.frame.origin.x && startViewPosition.y == strongSelf.view.frame.origin.y {
                    _ = strongSelf.controller.playOrPause()
                }
                startDragPosition = nil
                if let opacity = strongSelf.view.layer?.opacity, opacity < 0.5 {
                    let controller = strongSelf.controller
                    controller.notifyCompleteQueue(animated: true)
                    controller.cleanup()
                } else {
                    strongSelf.findCorner()
                }
                strongSelf.view._change(opacity: 1.0)
                
                return .invoked
            }
            return .rejected
        }, with: self, for: .leftMouseUp, priority: .high)
        
        window?.set(mouseHandler: { [weak self] (_) -> KeyHandlerResult in
            if let strongSelf = self, strongSelf.view._mouseInside() {
                startDragPosition = strongSelf.window?.mouseLocationOutsideOfEventStream
                startViewPosition = strongSelf.view.frame.origin
                
                return .invoked
            }
            return .rejected
        }, with: self, for: .leftMouseDown, priority: .high)
        
        window?.set(mouseHandler: { [weak self] (_) -> KeyHandlerResult in
            if let strongSelf = self, let startDragPosition = startDragPosition, let current = strongSelf.window?.mouseLocationOutsideOfEventStream, let frame = strongSelf.window?.contentView?.frame {
                let difference = NSMakePoint(startDragPosition.x - current.x, startDragPosition.y - current.y)
                let point = NSMakePoint(startViewPosition.x - difference.x, startViewPosition.y - difference.y)
                strongSelf.view.setFrameOrigin(point)
                
                if strongSelf.view.frame.maxX > frame.width {
                    let difference = strongSelf.view.frame.maxX - frame.width
                    strongSelf.view.layer?.opacity = (1.0 - Float(difference / strongSelf.view.frame.width))
                } else if point.x < 0 {
                    let difference = abs(point.x)
                    strongSelf.view.layer?.opacity = (1.0 - Float(difference / strongSelf.view.frame.width))
                } else {
                    strongSelf.view.layer?.opacity = 1.0
                }
                
                return .invoked
            }
            return .rejected
        }, with: self, for: .leftMouseDragged, priority: .high)
    }
    
    public func hide(_ animated:Bool = true) {
        isShown = false
        presentationGeneration &+= 1
        let generation = presentationGeneration
        displayedMessageId = nil
        displayedResourceId = nil
        dataDisposable.set(nil)
        fetchDisposable.set(nil)
        window?.removeAllHandlers(for: self)
        guard isLoaded() else {
            return
        }
        if let contentView = window?.contentView, genericView.superview != nil {
            let point:NSPoint
            switch alignment {
            case .topRight:
                point = NSMakePoint(contentView.frame.width, contentView.frame.height - view.frame.height - 130)
            case .topLeft:
                point = NSMakePoint(-view.frame.width, contentView.frame.height - view.frame.height - 130)
            case .bottomRight:
                point = NSMakePoint(contentView.frame.width, 100)
            case .bottomLeft:
                point = NSMakePoint(-view.frame.width, 100)
            }
            
            genericView._change(pos: point, animated: animated, completion: { [weak self, weak view] completed in
                if let self, self.isShown || self.presentationGeneration != generation {
                    return
                }
                (view as? InstantVideoPIPView)?.set(data: nil)
                (view as? InstantVideoPIPView)?.clear()
                view?.removeFromSuperview()
            })
        } else {
            genericView.set(data: nil)
            genericView.clear()
        }
    }
    
    func alignToCorner(_ corner:InstantVideoPIPCornerAlignment, _ animated: Bool = true) {
        if let contentView = window?.contentView {
            switch corner {
            case .topRight:
                genericView._change(pos: NSMakePoint(contentView.frame.width - view.frame.width - 20, contentView.frame.height - view.frame.height - 130), animated: animated)
            case .topLeft:
                genericView._change(pos: NSMakePoint(20, contentView.frame.height - view.frame.height - 130), animated: animated)
            case .bottomRight:
                genericView._change(pos: NSMakePoint(contentView.frame.width - view.frame.width - 20, 100), animated: animated)
            case .bottomLeft:
                genericView._change(pos: NSMakePoint(20, 100), animated: animated)
            }
        }
        
    }
    
    func findCorner() {
        if let contentView = window?.contentView {
            let center = NSMakePoint(contentView.frame.width/2, contentView.frame.height/2)
            let viewCenterPoint = NSMakePoint(view.frame.origin.x + view.frame.width/2, view.frame.origin.y + view.frame.height/2)
            if viewCenterPoint.x > center.x {
                if viewCenterPoint.y > center.y {
                    alignment = .topRight
                } else {
                    alignment = .bottomRight
                }
            } else {
                if viewCenterPoint.y > center.y {
                    alignment = .topLeft
                } else {
                    alignment = .bottomLeft
                }
            }
            alignToCorner(alignment)
        }
    }
    
    public func updateTableView(_ tableView:TableView?, context: any AccountContextProtocol, controller: APController) {
        let previousNavigation = self.context.bindings.rootNavigation()
        let navigation = context.bindings.rootNavigation()
        if controller !== self.controller || context.window !== __window {
            hide(false)
            self.currentMessage = nil
            self.timebase = nil
        }
        if previousNavigation !== navigation {
            previousNavigation.remove(listener: navigationListener)
            navigation.add(listener: navigationListener)
        }
        self.tableView?.removeScroll(listener: listener)
        self.tableView = tableView
        self.context = context
        self.__window = context.window
        self.tableView?.addScroll(listener: listener)
        if controller !== self.controller {
            self.controller.remove(listener: self)
            self.controller = controller
            controller.add(listener: self)
        }
        if let song = controller.currentSong {
            songDidChanged(song: song, for: controller, animated: false)
            playerDidChangedTimebase(song: song, for: controller, animated: false)
            songDidChangedState(song: song, for: controller, animated: false)
        } else {
            currentMessage = nil
            timebase = nil
            updateScrolled()
        }
    }
    
    
    
    public func songDidChanged(song:APSongItem, for controller:APController, animated: Bool) {
        guard controller === self.controller, controller.currentSong?.stableId == song.stableId else {
            return
        }
        var msg:Message? = nil
        switch song.entry {
        case let .song(message):
            if let md = (message.anyMedia as? TelegramMediaFile), md.isInstantVideo, song.state != .stoped {
                msg = message
            }
        default:
            break
        }
        
        if let msg = msg {
            if let currentMessage = currentMessage, !isShown && currentMessage.id != msg.id, CFAbsoluteTimeGetCurrent() - scrollTime > 1.0 {
                if let item = tableView?.item(stableId: msg.chatStableId) {
                    tableView?.scroll(to: .center(id: item.stableId, innerId: nil, animated: true, focus: .init(focus: false), inset: 0))
                }
            }
            
            currentMessage = msg
//            genericView.reset(with: controller.timebase, false)
            
        } else {
            currentMessage = nil
            self.timebase = nil
        }
        updateScrolled()
    }
    public func songDidChangedState(song: APSongItem, for controller: APController, animated: Bool) {
        guard controller === self.controller, song.stableId == currentMessage?.chatStableId else {
            return
        }
        switch song.state {
        case let .playing(_, _, progress):
            genericView.playingProgressView.state = .ImpossibleFetching(progress: Float(progress), force: false)
        case .stoped, .waiting, .fetching:
            genericView.playingProgressView.state = .None
        case let .paused(_, _, progress):
            genericView.playingProgressView.state = .ImpossibleFetching(progress: Float(progress), force: true)
        }
    }
    public func songDidStartPlaying(song:APSongItem, for controller:APController, animated: Bool) {
        
    }
    public func songDidStopPlaying(song:APSongItem, for controller:APController, animated: Bool) {
        if song.stableId == currentMessage?.chatStableId {
            //self.timebase = nil
        }
    }
    public func playerDidChangedTimebase(song:APSongItem, for controller:APController, animated: Bool) {
        guard controller === self.controller else {
            return
        }
        if song.stableId == currentMessage?.chatStableId {
            self.timebase = controller.timebase
        }
    }

    public func audioDidCompleteQueue(for controller:APController, animated: Bool) {
        guard controller === self.controller else {
            return
        }
        currentMessage = nil
        timebase = nil
        hide(animated)
    }
    
}
