import Cocoa
import TGUIKit
import TelegramCore
import TelegramMedia
import Postbox
import SwiftSignalKit
import RangeSet
import AudioPlayerCore
import ChatUI
import PeerMediaUI
import GalleryUI
import ChatHistoryModel
import ChatModeTypes
import TelegramUtils
import TelegramContext
import TelegramTheme
import TelegramMediaUtils
import MessageUtils
import GeneralRows
import LocalAnimations
import Localization


private final class PlayerListArguments {
    let chatInteraction: ChatInteraction
    let music:(Message, GalleryAppearType)->Void
    let toggleProfile:(FileMediaReference, Bool)->Void
    let contextMenuItems:(Message)->[ContextMenuItem]
    init(chatInteraction: ChatInteraction, music:@escaping(Message, GalleryAppearType)->Void, toggleProfile: @escaping (FileMediaReference, Bool) -> Void, contextMenuItems:@escaping(Message)->[ContextMenuItem]) {
        self.chatInteraction = chatInteraction
        self.music = music
        self.toggleProfile = toggleProfile
        self.contextMenuItems = contextMenuItems
    }
}

private enum PlayerListEntry: TableItemListNodeEntry {
    static func < (lhs: PlayerListEntry, rhs: PlayerListEntry) -> Bool {
        return lhs.index < rhs.index
    }
    
    var index: MessageIndex {
        switch self {
        case let .message(_, message):
            return MessageIndex(message)
        case .separator:
            return MessageIndex.absoluteLowerBound()
        case .empty:
            return MessageIndex.absoluteLowerBound()
        }
    }
    
    case message(sectionId: Int32, Message)
    case separator(sectionId: Int32, text: String)
    case empty(sectionId: Int32, text: String)
    var stableId: ChatHistoryEntryId {
        switch self {
        case let .message(_, message):
            return .message(message)
        case let .separator(sectionId, _):
            return .maybeId(sectionId)
        case let .empty(sectionId, _):
            return .maybeId(sectionId + 100000)
        }
    }
    
    func item(_ arguments: PlayerListArguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case let .message(_, message):
            return PeerMediaMusicRowItem(initialSize, arguments.chatInteraction, .messageEntry(message, [], .defaultSettings, .singleItem), isCompactPlayer: true, music: arguments.music, contextMenuItems: arguments.contextMenuItems)
        case let .separator(_, text):
            return SeparatorRowItem(initialSize, stableId, string: text)
        case let .empty(_, text):
            return SearchEmptyRowItem(initialSize, stableId: stableId, text: text)
        }
    }
    
    static func ==(lhs: PlayerListEntry, rhs: PlayerListEntry) -> Bool {
        switch lhs {
        case let .message(_, lhsMessage):
            if case let .message(_, rhsMessage) = rhs {
                return isEqualMessages(lhsMessage, rhsMessage)
            } else {
                return false
            }
        case let .separator(sectionId, text):
            if case .separator(sectionId, text) = rhs {
                return true
            } else {
                return false
            }
        case let .empty(sectionId, text):
            if case .empty(sectionId, text) = rhs {
                return true
            } else {
                return false
            }
        }
    }
}


private func playerAudioEntries(_ update: PeerMediaUpdate, source: PlayerListController.Source, context: any AccountContextProtocol) -> [PlayerListEntry] {
    var entries: [PlayerListEntry] = []
    let sectionId: Int32 = 0
    
    let messages = expandSharedMediaMessages(update.messages, where: sharedMediaPredicate(for: .music))
    for message in messages {
        guard let file = message.media.first as? TelegramMediaFile, file.isMusic else {
            continue
        }
        entries.append(.message(sectionId: sectionId, message))
    }
    
    if !entries.isEmpty {
        switch source {
        case .chat:
            entries.append(.separator(
                sectionId: sectionId,
                text: strings().audioPlaylistSeparatorChat
            ))
        case let .profile(peer, _, _, _):
            if peer.id == context.peerId {
                entries.append(.separator(
                    sectionId: sectionId,
                    text: strings().audioPlaylistSeparatorYour
                ))
            } else {
                entries.append(.separator(
                    sectionId: sectionId,
                    text: strings().audioPlaylistSeparatorUser(peer._asPeer().compactDisplayTitle)
                ))
            }
        }
    } else {
        entries.append(.empty(
            sectionId: sectionId,
            text: strings().audioPlaylistEmpty
        ))
    }

    
    
    return entries.sorted(by: <)
}
fileprivate func preparedAudioListTransition(from fromView:[PlayerListEntry], to toView:[PlayerListEntry], initialSize:NSSize, arguments: PlayerListArguments, animated:Bool, scroll:TableScrollState) -> TableUpdateTransition {
    let (removed,inserted,updated) = proccessEntriesWithoutReverse(fromView, right: toView, { (entry) -> TableRowItem in
        
        return entry.item(arguments, initialSize: initialSize)
        
    })
    
    for item in inserted {
        _ = item.1.makeSize(initialSize.width, oldWidth: initialSize.width)
    }
    for item in updated {
        _ = item.1.makeSize(initialSize.width, oldWidth: initialSize.width)
    }
    
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated:updated, animated:animated, state:scroll)
}



private final class PlayerListTrackView: View {
    private let cover: TransformImageView = TransformImageView()
    private let trackName: TextView = TextView()
    let artistName: TextView = TextView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(cover)
        addSubview(trackName)
        addSubview(artistName)
        
        trackName.userInteractionEnabled = false
        trackName.isSelectable = false
        
        artistName.isSelectable = false
        
        artistName.set(handler: { control in
            control.alphaValue = 1
        }, for: .Hover)
        
        artistName.set(handler: { control in
            control.alphaValue = 1
        }, for: .Normal)
        
        artistName.set(handler: { control in
            control.alphaValue = 0.8
        }, for: .Highlight)
        
        updateLocalizationAndTheme(theme: theme)
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        trackName.background = theme.colors.background
        artistName.background = theme.colors.background
    }
    
    func update(_ item: APSongItem) {
        let trackLayout = TextViewLayout(.initialize(string: item.songName.isEmpty ? item.performerName : item.songName, color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1)
        
        let artistLayout = TextViewLayout(.initialize(string: item.performerName, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)

        trackName.update(trackLayout)
        artistName.update(artistLayout)
        
        let imageCorners = ImageCorners(topLeft: .Corner(4.0), topRight: .Corner(4.0), bottomLeft: .Corner(4.0), bottomRight: .Corner(4.0))
        let arguments = TransformImageArguments(corners: imageCorners, imageSize: PeerMediaIconSize, boundingSize: PeerMediaIconSize, intrinsicInsets: NSEdgeInsets())
        
        cover.layer?.contents = theme.icons.playerMusicPlaceholder
        cover.layer?.cornerRadius = .cornerRadius
        if let fileMediaReference = item.coverFileMediaReference {
            cover.setSignal(chatMessageImageFile(account: item.account, fileReference: fileMediaReference, scale: System.backingScale))
        }
        cover.set(arguments: arguments)
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        
        cover.setFrameSize(PeerMediaIconSize)
        
        trackName.resize(frame.width - 60)
        artistName.resize(frame.width - 60)

        trackName.setFrameOrigin(NSMakePoint(50, 2))
        artistName.setFrameOrigin(NSMakePoint(50, frame.height - artistName.frame.height - 2))
        
        cover.centerY(x: 0)

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class PlayerListHandlingView: View {
    fileprivate let playPause = Button()
    private let playPauseView = LottiePlayerView()
    fileprivate let prev = ImageButton()
    fileprivate let next = ImageButton()
    fileprivate let order = ImageButton()
    fileprivate let iteration = ImageButton()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(playPause)
        addSubview(prev)
        addSubview(next)
        addSubview(order)
        addSubview(iteration)
        playPause.addSubview(playPauseView)
        playPause.setFrameSize(NSMakeSize(40, 40))
        
        playPauseView.setFrameSize(playPause.frame.size)
        
        prev.setAccessibilityLabel(strings().voiceOverCommonPrevious)
        next.setAccessibilityLabel(strings().voiceOverCommonNext)
        playPause.setAccessibilityLabel(strings().voiceOverCommonPlay)
        order.setAccessibilityLabel(strings().voiceOverCommonPlaybackOrder)
        iteration.setAccessibilityLabel(strings().dateSelectorScheduleRepeat)

        prev.autohighlight = false
        next.autohighlight = false
        playPause.autohighlight = false
        iteration.autohighlight = false
        order.autohighlight = false

        prev.scaleOnClick = true
        next.scaleOnClick = true
        playPause.scaleOnClick = true
        iteration.scaleOnClick = true
        order.scaleOnClick = true

        updateLocalizationAndTheme(theme: theme)

    }
    
    override func layout() {
        super.layout()
        playPause.centerX()
        playPause.centerY(addition: -1)
        prev.centerY(x: playPause.frame.minX - prev.frame.width - 10)
        next.centerY(x: playPause.frame.maxX + 10)
        iteration.centerY(x: frame.width - iteration.frame.width)
        order.centerY(x: 0)
    }
        
    func update(_ item: APSongItem, controller: APController, animated: Bool) {
        
        next.userInteractionEnabled = controller.nextEnabled
        prev.userInteractionEnabled = controller.prevEnabled

        switch controller.nextEnabled {
        case true:
            next.set(image: theme.icons.playlist_next, for: .Normal)
        case false:
            next.set(image: theme.icons.playlist_next_locked, for: .Normal)
        }
        
        switch controller.prevEnabled {
        case true:
            prev.set(image: theme.icons.playlist_prev, for: .Normal)
        case false:
            prev.set(image: theme.icons.playlist_prev_locked, for: .Normal)
        }
        
        switch controller.state.status {
        case .playing:
            playPause.setAccessibilityLabel(strings().voiceOverCommonPause)
            play(animated: animated, sticker: LocalAnimatedSticker.playlist_play_pause)
        case .paused:
            playPause.setAccessibilityLabel(strings().voiceOverCommonPlay)
            play(animated: animated, sticker: LocalAnimatedSticker.playlist_pause_play)
        default:
            break
        }
        
        switch controller.state.orderState {
        case .normal:
            order.setAccessibilityValue(nil)
            order.set(image: theme.icons.playlist_order_normal, for: .Normal)
        case .reversed:
            order.setAccessibilityValue(strings().voiceOverCommonReversed)
            order.set(image: theme.icons.playlist_order_reversed, for: .Normal)
        case .random:
            order.setAccessibilityValue(strings().voiceOverCommonShuffle)
            order.set(image: theme.icons.playlist_order_random, for: .Normal)
        }
        
        switch controller.state.repeatState {
        case .none:
            iteration.setAccessibilityValue(strings().dateSelectorScheduleRepeatNever)
            iteration.set(image: theme.icons.playlist_repeat_none, for: .Normal)
        case .one:
            iteration.setAccessibilityValue(strings().voiceOverCommonRepeatOne)
            iteration.set(image: theme.icons.playlist_repeat_one, for: .Normal)
        case .circle:
            iteration.setAccessibilityValue(strings().voiceOverCommonRepeatAll)
            iteration.set(image: theme.icons.playlist_repeat_circle, for: .Normal)
        }
        order.sizeToFit()
        iteration.sizeToFit()
        next.sizeToFit()
        prev.sizeToFit()
        needsLayout = true
    }
    private func play(animated: Bool, sticker: LocalAnimatedSticker) {
        let data = sticker.data
        if let data = data {
            
            let current: Int32
            let total: Int32
            if playPauseView.animation?.key.key != LottieAnimationKey.bundle(sticker.rawValue) {
                current = playPauseView.currentFrame ?? 0
                total = playPauseView.totalFrames ?? 0
            } else {
                current = 0
                total = playPauseView.currentFrame ?? 0
            }
            let animation = LottieAnimation(compressed: data, key: .init(key: .bundle(sticker.rawValue), size: NSMakeSize(46, 46)), cachePurpose: .none, playPolicy: .toEnd(from: animated ? total - current : .max), colors: [.init(keyPath: "", color: theme.colors.text)], runOnQueue: .mainQueue())
            playPauseView.set(animation)
        }
    }
        
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)

    }
}

private final class PlayerListControlsView : View {
    private let separator: View = View()
    fileprivate var trackView: PlayerListTrackView?
    fileprivate let progress: LinearProgressControl = LinearProgressControl(progressHeight: 5)
    private let playedView: TextView = TextView()
    private let restView: TextView = TextView()
    fileprivate let handlings: PlayerListHandlingView = PlayerListHandlingView(frame: .zero)
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(progress)
        addSubview(playedView)
        addSubview(restView)
        addSubview(handlings)
        addSubview(separator)
        updateLocalizationAndTheme(theme: theme)
        separator.layer?.opacity = 0
        
    }
    
    var searchClick:((String)->Void)? = nil
    
    private var track: APSongItem?
    
    func update(_ track: APSongItem, controller: APController, animated: Bool) {
        if track != self.track {
            if let current = self.trackView {
                self.trackView = nil
                if animated {
                    current.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak current] _ in
                        current?.removeFromSuperview()
                    })
                } else {
                    current.removeFromSuperview()
                }
            }
            let trackView = PlayerListTrackView(frame: NSMakeRect(10, 10, frame.width - 20, 40))
            self.trackView = trackView
            addSubview(trackView)
            trackView.update(track)
            let trackName = track.performerName
            
            trackView.artistName.set(handler: { [weak self] _ in
                self?.searchClick?(trackName)
            }, for: .Click)
            
            if animated {
                trackView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
        }
        
        self.track = track
        
        var played: Int? = nil
        var rest: Int? = nil

        handlings.update(track, controller: controller, animated: animated)
        
        switch track.state {
        case .waiting:
            self.progress.set(progress: 0, animated: animated)
        case .stoped:
            self.progress.set(progress: 0, animated: animated)
        case let .playing(current, duration, progress), let .paused(current, duration, progress):
            self.progress.set(progress: CGFloat(progress.isFinite ? min(max(progress, 0), 1) : 0), animated: animated, duration: 0.2)
            if current.isFinite {
                var current = max(0, current)
                if duration.isFinite, duration >= 0 {
                    current = min(current, duration)
                    rest = Int(exactly: (duration - current).rounded(.towardZero))
                }
                played = Int(exactly: current.rounded(.towardZero))
            }
        case let .fetching(progress):
            self.progress.set(progress: CGFloat(progress.isFinite ? min(max(progress, 0), 1) : 0), animated: animated)
        }
        
        let playedLayout = TextViewLayout.init(.initialize(string: played.map { timerText($0) } ?? " ", color: theme.colors.grayText, font: .normal(.short)))
        let restLayout = TextViewLayout.init(.initialize(string: rest.map { timerText($0) } ?? " ", color: theme.colors.grayText, font: .normal(.short)))

        playedLayout.measure(width: .greatestFiniteMagnitude)
        restLayout.measure(width: .greatestFiniteMagnitude)
            
        self.playedView.update(playedLayout)
        self.restView.update(restLayout)
        needsLayout = true
    }
    

    
    override func layout() {
        separator.frame = NSMakeRect(0, frame.height - .borderSize, frame.width, .borderSize)
        trackView?.frame = NSMakeRect(10, 10, frame.width - 20, 40)
        progress.frame = NSMakeRect(10, 60, frame.width - 20, 12)
        
        playedView.setFrameOrigin(NSMakePoint(progress.frame.minX, progress.frame.maxY + 3))
        restView.setFrameOrigin(NSMakePoint(progress.frame.maxX - restView.frame.width, progress.frame.maxY + 3))
        
        handlings.frame = NSMakeRect(10, restView.frame.maxY, frame.width - 20, 40)
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        separator.backgroundColor = theme.colors.border
        
        progress.insets = NSEdgeInsetsMake(0, 0, 0, 0)
        progress.scrubberImage = generateImage(NSMakeSize(8, 8), contextGenerator: { size, ctx in
            let rect = CGRect(origin: .zero, size: size)
            ctx.clear(rect)
            ctx.setFillColor(theme.colors.accent.cgColor)
            ctx.fillEllipse(in: rect)
        })
        progress.roundCorners = true
        progress.alignment = .center
        progress.liveScrobbling = false
        progress.fetchingColor = theme.colors.grayIcon.withAlphaComponent(0.6)
        progress.containerBackground = theme.colors.grayIcon.withAlphaComponent(0.2)
        progress.style = ControlStyle(foregroundColor: theme.colors.accent, backgroundColor: .clear, highlightColor: .clear)
        progress.set(progress: 0, animated: false, duration: 0)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    fileprivate func updateScroll(_ position: ScrollPosition, tableFrame: NSRect) {
        separator.change(opacity: position.rect.minY > tableFrame.height ? 1 : 0)
    }
}

private struct State: Equatable {
    var song: APSongItem?
    var savedIds: Set<Int64>?
}


final class PlayerListView : View, APDelegate {
    
    
    let tableView: TableView
    private let controls: PlayerListControlsView = PlayerListControlsView(frame: .zero)
    private var addToProfileView: TextButton?
    private var addedToProfileView: TextView?
    private let bufferingStatusDisposable = MetaDisposable()
    
    deinit {
        controller?.remove(listener: self)
        bufferingStatusDisposable.dispose()
    }
    
    var playerDidUpdate:((APSongItem?)->Void)? = nil
    
    private(set) var controller:APController? {
        didSet {
            oldValue?.remove(listener: self)
            self.bufferingStatusDisposable.set(nil)
            self.updateStatus(RangeSet(), 0)
            controller?.add(listener: self)
            if let controller = controller {
                self.bufferingStatusDisposable.set((controller.bufferingStatus
                    |> deliverOnMainQueue).start(next: { [weak self, weak controller] status in
                        guard let self, let controller, self.controller === controller else { return }
                        if let status = status {
                            self.updateStatus(status.0, status.1)
                        } else {
                            self.updateStatus(RangeSet(), 0)
                        }
                    }))
            } else {
                self.bufferingStatusDisposable.set(nil)
            }
        }
    }
    
    func updateStatus(_ ranges: RangeSet<Int64>, _ size: Int64) {
        controls.progress.set(fetchingProgressRanges: audioPlayerBufferingRanges(ranges, size: size), animated: false)
    }
    
    fileprivate func updateState(_ state: State, animated: Bool, arguments: PlayerListArguments) {
        
        var addedToProfile: Bool? = nil
        var currentFileReference: FileMediaReference? = nil
        if let song = state.song, let savedIds = state.savedIds  {
            switch song.entry {
            case let .song(message):
                if let file = message.file {
                    addedToProfile = savedIds.contains(file.fileId.id)
                    currentFileReference = FileMediaReference.message(message: MessageReference.init(message), media: file)
                }
            case let .savedMusic(reference, _):
                addedToProfile = savedIds.contains(reference.media.fileId.id)
                currentFileReference = reference
            default:
                addedToProfile = nil
            }
        }
        
        if let addedToProfile, let currentFileReference {
            if !addedToProfile {
                
                if let addedToProfileView {
                    performSubviewRemoval(addedToProfileView, animated: animated)
                    self.addedToProfileView = nil
                }
                
                let current: TextButton
                let isNew: Bool
                if let view = self.addToProfileView {
                    current = view
                    isNew = false
                } else {
                    current = TextButton()
                    self.addSubview(current)
                    current.autohighlight = false
                    current.scaleOnClick = true
                    current.layer?.cornerRadius = 10
                    self.addToProfileView = current
                    isNew = true
                }
                
                current.setSingle(handler: { _ in
                    arguments.toggleProfile(currentFileReference, !addedToProfile)
                }, for: .Click)
                
                current.set(background: theme.colors.accent, for: .Normal)
                current.set(text: strings().audioPlaylistButtonAddToProfile, for: .Normal)
                current.set(font: .medium(.text), for: .Normal)
                current.set(color: theme.colors.underSelectedColor, for: .Normal)
                current.sizeToFit(.zero, NSMakeSize(frame.width - 20, 40), thatFit: true)
                
                if isNew {
                    current.centerX(y: 140)
                }
            } else {
                if let addToProfileView {
                    performSubviewRemoval(addToProfileView, animated: animated)
                    self.addToProfileView = nil
                }
                
                let current: TextView
                let isNew: Bool
                if let view = self.addedToProfileView {
                    current = view
                    isNew = false
                } else {
                    current = TextView()
                    current.userInteractionEnabled = true
                    current.isSelectable = false
                    self.addedToProfileView = current
                    self.addSubview(current)
                    isNew = true
                }
                let attr = parseMarkdownIntoAttributedString(
                    strings().audioPlaylistProfileNotice,
                    attributes: .init(
                        body: .init(font: .normal(.short), textColor: theme.colors.grayText),
                        link: .init(font: .normal(.short), textColor: theme.colors.accent),
                        linkAttribute: { contents in
                            return (NSAttributedString.Key.link.rawValue, contents)
                        }
                    )
                )
                
                let layout = TextViewLayout(attr, alignment: .center)
                layout.measure(width: frame.width - 20)
                
                layout.interactions = .init(processURL: { _ in
                    arguments.toggleProfile(currentFileReference, !addedToProfile)
                })
                current.update(layout)

                if isNew {
                    current.centerX(y: 140)
                }
                
            }
        } else {
            if let addedToProfileView {
                performSubviewRemoval(addedToProfileView, animated: animated)
                self.addedToProfileView = nil
            }
            if let addToProfileView {
                performSubviewRemoval(addToProfileView, animated: animated)
                self.addToProfileView = nil
            }
        }
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        self.updateLayout(size: self.frame.size, transition: transition)
    }
    
    required init(frame frameRect: NSRect) {
        tableView = TableView(frame: .zero)
        super.init(frame: frameRect)
        addSubview(tableView)
        addSubview(controls)
        
        controls.progress.onUserChanged = { [weak self] progress in
            self?.controller?.set(trackProgress: progress)
            self?.controls.progress.set(progress: CGFloat(progress), animated: false)
        }
        
        
//        controls.progress.startScrobbling = { [weak self]  in
//            guard let controller = self?.controller else {
//                return
//            }
//            if controller.isPlaying {
//                _ = self?.controller?.pause()
//                paused = true
//            } else {
//                paused = false
//            }
//        }
//        
//        controls.progress.endScrobbling = { [weak self]  in
//            if paused {
//                DispatchQueue.main.async {
//                    _ = self?.controller?.play()
//                }
//            }
//        }
        
        controls.handlings.next.set(handler: { [weak self] _ in
            self?.controller?.next()
            self?.scrollToCurrent()
        }, for: .Click)
        
        controls.handlings.prev.set(handler: { [weak self] _ in
            self?.controller?.prev()
            self?.scrollToCurrent()
        }, for: .Click)
        
        controls.handlings.playPause.set(handler: { [weak self] _ in
            _ = self?.controller?.playOrPause()
        }, for: .Click)

        controls.handlings.iteration.set(handler: { [weak self] _ in
            self?.controller?.nextRepeatState()
        }, for: .Click)
        
        controls.handlings.order.set(handler: { [weak self] _ in
            self?.controller?.nextOrderState()
        }, for: .Click)
        
        tableView.addScroll(listener: TableScrollListener(dispatchWhenVisibleRangeUpdated: false, { [weak self] position in
            if let `self` = self {
                self.controls.updateScroll(position, tableFrame: self.tableView.frame)
            }
        }))
        
        controls.searchClick = { [weak self] text in
            let context = self?.controller?.context
            if let context = context {
                AudioPlayerUIHooks.shared.focusSearch(context, text)
            }
        }
    }
    
    
    func setController(_ controller: APController?) {
        self.controller = controller
        self.controls.isHidden = controller?.currentSong == nil
        if let controller = controller, let item = controller.currentSong {
            self.controls.update(item, controller: controller, animated: false)
        }
        self.playerDidUpdate?(controller?.currentSong)
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        controller?.notifyGlobalStateChanged(animated: false)
    }
    
    private func scrollToCurrent() {
        if let entry = controller?.currentSong?.entry {
            switch entry {
            case let .song(message):
                self.tableView.scroll(to: .center(id: PeerMediaSharedEntryStableId.messageId(message.id), innerId: nil, animated: true, focus: .init(focus: false), inset: 0))
            default:
                break
            }
        }
    }
    
    
    private func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
        
        var tableOffset: CGFloat = 140
        
        if let addToProfileView {
            transition.updateFrame(view: addToProfileView, frame: addToProfileView.centerFrameX(y: tableOffset))
            tableOffset += addToProfileView.frame.height + 15
        } else if let addedToProfileView {
            transition.updateFrame(view: addedToProfileView, frame: addedToProfileView.centerFrameX(y: tableOffset))
            tableOffset += addedToProfileView.frame.height + 15
        }
        
        transition.updateFrame(view: controls, frame: NSMakeRect(0, 0, size.width, tableOffset))
        
        
        transition.updateFrame(view: tableView, frame: NSMakeRect(0, tableOffset, size.width, size.height - tableOffset))
    }
    
    override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func update(_ song: APSongItem, controller: APController, animated: Bool) {
        guard self.controller === controller, controller.currentSong?.stableId == song.stableId else { return }
        self.controls.isHidden = false
        self.controls.update(song, controller: controller, animated: animated)
        playerDidUpdate?(song)
    }

    func songDidChanged(song: APSongItem, for controller: APController, animated: Bool) {
        self.update(song, controller: controller, animated: animated)
    }
    
    func songDidChangedState(song: APSongItem, for controller: APController, animated: Bool) {
        self.update(song, controller: controller, animated: animated)
    }
    
    func songDidStartPlaying(song: APSongItem, for controller: APController, animated: Bool) {
        self.update(song, controller: controller, animated: animated)
    }
    
    func songDidStopPlaying(song: APSongItem, for controller: APController, animated: Bool) {
        self.update(song, controller: controller, animated: animated)
    }
    
    func playerDidChangedTimebase(song: APSongItem, for controller: APController, animated: Bool) {
        self.update(song, controller: controller, animated: animated)
    }
    
    func audioDidCompleteQueue(for controller: APController, animated: Bool) {
        guard self.controller === controller else { return }
        self.controls.isHidden = true
        self.updateStatus(RangeSet(), 0)
        playerDidUpdate?(nil)
    }
    
}


public class PlayerListController: ModalViewController {
    
    public override var defaultBarTitle: String {
        return localizedString("Telegram.PlayerListController")
    }
    
    public enum Source {
        case chat(PeerId, MessageIndex, [Message])
        case profile(EnginePeer, TelegramMediaFile, ProfileSavedMusicContext.State?, ProfileSavedMusicContext)
        
        public var peerId: PeerId {
            switch self {
            case let .chat(peerId, _, _):
                return peerId
            case let .profile(peer, _, _, _):
                return peer.id
            }
        }
        public var messageIndex: MessageIndex {
            switch self {
            case let .chat(_, messageIndex, _):
                return messageIndex
            case let .profile(peer, file, _, _):
                return MessageIndex(id: MessageId(peerId: peer.id, namespace: 0, id: Int32(clamping: file.fileId.id)), timestamp: Int32.max)
            }
        }
    }
    
    private let audioPlayer: InlineAudioPlayerView
    private let chatInteraction: ChatInteraction
    private let disposable = MetaDisposable()
    private let source: Source
    private let context: any AccountContextProtocol
    private let profileSavedMusic: ProfileSavedMusicContext?
    
    public init(audioPlayer: InlineAudioPlayerView, context: any AccountContextProtocol, currentContext: any AccountContextProtocol, source: Source) {
        self.chatInteraction = ChatInteraction(chatLocation: .peer(source.peerId), context: context)
        self.source = source
        self.audioPlayer = audioPlayer
        self.context = context
        
        switch source {
        case .chat:
            self.profileSavedMusic = nil
        case let .profile(_, _, _, savedContext):
            self.profileSavedMusic = savedContext
        }
        
        super.init(frame: NSMakeRect(0, 0, 300, 500))
        
        
        chatInteraction.inlineAudioPlayer = { [weak self] controller in
            let object = InlineAudioPlayerView.ContextObject(controller: controller, context: currentContext, tableView: self?.tableView, supportTableView: nil)
            self?.audioPlayer.update(with: object)
            self?.genericView.setController(controller)
        }
    }
    
    var genericView: PlayerListView {
        return self.view as! PlayerListView
    }
    
    public override func viewClass() -> AnyClass {
        return PlayerListView.self
    }
    
    var tableView: TableView {
        return genericView.tableView
    }
    
    deinit {
        disposable.dispose()
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        window?.set(handler: { [weak self] event in
            self?.genericView.controller?.prev()
            return .invoked
        }, with: self, for: .LeftArrow, priority: .modal)
        
        window?.set(handler: { [weak self] event in
            self?.genericView.controller?.next()
            return .invoked
        }, with: self, for: .RightArrow, priority: .modal)
    }
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.removeObserver(for: self)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        let actionsDisposable = DisposableSet()
        
        let initialState = State(song: self.audioPlayer.controller?.currentSong)
        
        let statePromise = ValuePromise(initialState, ignoreRepeated: true)
        let stateValue = Atomic(value: initialState)
        let updateState: ((State) -> State) -> Void = { f in
            statePromise.set(stateValue.modify (f))
        }
        
        genericView.playerDidUpdate = { song in
            updateState { current in
                var current = current
                current.song = song
                return current
            }
        }
    
        actionsDisposable.add((context.engine.peers.savedMusicIds() |> deliverOnMainQueue).startStrict(next: { savedIds in
            updateState { current in
                var current = current
                current.savedIds = savedIds ?? Set()
                return current
            }
        }))
        
        onDeinit = {
            actionsDisposable.dispose()
        }
        
        let chatLocationInput = (self.audioPlayer.controller as? APChatController)?.chatLocationInput
        
        tableView.getBackgroundColor = {
            return theme.colors.background
        }
                
        let location = ValuePromise<ChatHistoryLocation>(ignoreRepeated: true)
        
        let historyViewUpdate = location.get() |> deliverOnMainQueue
            |> mapToSignal { [weak self] location -> Signal<(PeerMediaUpdate, TableScrollState?), NoError> in
                
                guard let `self` = self else {return .complete()}
                
                return chatHistoryViewForLocation(location, context: self.chatInteraction.interactionContext, chatLocation: self.chatInteraction.chatLocation, fixedCombinedReadStates: nil, tag: .tag(.music), additionalData: [], chatLocationInput: chatLocationInput) |> mapToQueue { view -> Signal<(PeerMediaUpdate, TableScrollState?), NoError> in
                    switch view {
                    case .Loading:
                        return .single((PeerMediaUpdate(), nil))
                    case let .HistoryView(view: view, _, scroll, _):
                        var messages:[Message] = []
                        for entry in view.entries {
                             messages.append(entry.message)
                        }
                        let laterId = view.laterId
                        let earlierId = view.earlierId

                        var state: TableScrollState?
                        if let scroll = scroll {
                            switch scroll {
                            case let .index(_, position, _, _):
                                state = position
                            default:
                                break
                            }
                        }
                        return .single((PeerMediaUpdate(messages: messages, updateType: .history, laterId: laterId, earlierId: earlierId), state))
                    }
                }
        }
        
        let animated: Atomic<Bool> = Atomic(value: false)
        let context = self.chatInteraction.interactionContext
        let previous:Atomic<[PlayerListEntry]> = Atomic(value: [])
        let updateView = Atomic<PeerMediaUpdate?>(value: nil)
        let source = self.source
        _ = source.peerId
        
        
        let arguments = PlayerListArguments(chatInteraction: chatInteraction, music: { message, _ in
            _ = AudioPlayerUIHooks.shared.getAudioPlayer(context)?.playOrPause(message.id)
        }, toggleProfile: { [weak self] file, add in
            if let profileSavedMusic = self?.profileSavedMusic {
                if add {
                    _ = profileSavedMusic.addMusic(file: file).start()
                } else {
                    _ = profileSavedMusic.removeMusic(file: file).start()
                }
            } else {
                if add {
                    _ = context.engine.peers.addSavedMusic(file: file).start()
                } else {
                    _ = context.engine.peers.removeSavedMusic(file: file).start()
                }
            }
            
        }, contextMenuItems: { [weak self] message in
            let state = stateValue.with { $0 }
            var items: [ContextMenuItem] = []
            if let file = message.file {
                let contains = state.savedIds?.contains(file.fileId.id) ?? false
                
                let saveToMenu = ContextMenu()
                
                let saveToItem = ContextMenuItem(strings().audioPlaylistContextSaveTo)

                if !contains {
                    saveToMenu.addItem(ContextMenuItem(
                        strings().audioPlaylistContextSaveToProfile,
                        handler: {
                            if let profileSavedMusic = self?.profileSavedMusic {
                                _ = profileSavedMusic.addMusic(file: FileMediaReference.standalone(media: file)).start()
                            } else {
                                _ = context.engine.peers.addSavedMusic(file: FileMediaReference.standalone(media: file)).start()
                            }
                            showModalText(for: context.window, text: strings().audioPlaylistAlertAddedToProfile)
                        }
                    ))
                }

                saveToMenu.addItem(ContextMenuItem(
                    strings().audioPlaylistContextSaveToSavedMessages,
                    handler: {
                        let _ = Sender.enqueue(media: file, context: context, peerId: context.peerId, replyId: nil, threadId: nil).start()
                        showModalText(for: context.window, text: strings().audioPlaylistAlertSavedSuccess)
                    }
                ))

                saveToItem.submenu = saveToMenu
                
                items.append(saveToItem)
                
                
                if contains {
                    items.append(ContextSeparatorItem())
                    items.append(ContextMenuItem(
                        strings().audioPlaylistContextRemoveFromProfile,
                        handler: {
                            if let profileSavedMusic = self?.profileSavedMusic {
                                _ = profileSavedMusic.removeMusic(file: FileMediaReference.standalone(media: file)).start()
                            } else {
                                _ = context.engine.peers.removeSavedMusic(file: FileMediaReference.standalone(media: file)).start()
                            }
                            showModalText(for: context.window, text: strings().audioPlaylistAlertRemovedFromProfile)
                        },
                        itemMode: .destruct,
                        itemImage: MenuAnimation.menu_delete.value
                    ))
                }

            }
            return items
        })
        
        let historyViewTransition: Signal<TableUpdateTransition, NoError>
        switch source {
        case let .chat(_, messageIndex, messages):
            
            if messages.isEmpty {
                historyViewTransition = historyViewUpdate |> deliverOnPrepareQueue |> map { update, scroll -> TableUpdateTransition in
                    let animated = animated.swap(true)
                    let scroll:TableScrollState = scroll ?? (animated ? .none(nil) : .saveVisible(.upper, false))
                    
                    let entries = playerAudioEntries(update, source: source, context: context)
                    _ = updateView.swap(update)
                    
                    return preparedAudioListTransition(from: previous.swap(entries), to: entries, initialSize: NSMakeSize(300, 0), arguments: arguments, animated: animated, scroll: scroll)
                    
                    } |> deliverOnMainQueue
            } else {
                let update = PeerMediaUpdate(messages: messages, updateType: .search, laterId: nil, earlierId: nil, automaticDownload: .defaultSettings, searchState: .init(state: .None, request: nil))
                let entries = playerAudioEntries(update, source: source, context: context)
                _ = updateView.swap(update)
                let transition = preparedAudioListTransition(from: previous.swap(entries), to: entries, initialSize: NSMakeSize(300, 0), arguments: arguments, animated: false, scroll: .none(nil))
                historyViewTransition = .single(transition)
            }
            
            
            location.set(.Navigation(index: MessageHistoryAnchorIndex.message(messageIndex), anchorIndex: MessageHistoryAnchorIndex.message(messageIndex), count: 50, side: .upper))
            
            tableView.setScrollHandler { scroll in
                let view = updateView.modify({$0})
                if let view = view {
                    var messageIndex:MessageIndex?
                    switch scroll.direction {
                    case .bottom:
                        messageIndex = view.earlierId
                    case .top:
                        messageIndex = view.laterId
                    case .none:
                        break
                    }
                    
                    if let messageIndex = messageIndex {
                        let _ = animated.swap(false)
                        location.set(.Navigation(index: MessageHistoryAnchorIndex.message(messageIndex), anchorIndex: MessageHistoryAnchorIndex.message(messageIndex), count: 50, side: scroll.direction == .bottom ? .lower : .upper))
                    }
                }
            }
            
        case let .profile(peer, _, _, profileContext):
            
            
            
            let messages: Signal<[Message], NoError> = profileContext.state |> map { state in
                var messages: [Message] = []
                for (i, file) in state.files.reversed().enumerated() {
                    let id = mapInt64ToInt32(file.fileId.id)
                    messages.append(.init(file, stableId: UInt32(id), messageId: MessageId(peerId: peer.id, namespace: 0, id: id), timestamp: Int32.max - Int32(i)))
                }
                return messages
            } |> deliverOnMainQueue
            
            historyViewTransition = messages |> mapToSignal { messages in
                let update = PeerMediaUpdate(messages: messages, updateType: .search, laterId: nil, earlierId: nil, automaticDownload: .defaultSettings, searchState: .init(state: .None, request: nil))
                let entries = playerAudioEntries(update, source: source, context: context)
                _ = updateView.swap(update)
                let transition = preparedAudioListTransition(from: previous.swap(entries), to: entries, initialSize: NSMakeSize(300, 0), arguments: arguments, animated: false, scroll: .none(nil))
                return .single(transition)
            }
            
            tableView.setScrollHandler { [weak profileContext] scroll in
                switch scroll.direction {
                case .bottom:
                    profileContext?.loadMore()
                case .top:
                    break
                case .none:
                    break
                }
            }
        }
        
        var first: Bool = true
        actionsDisposable.add((statePromise.get() |> deliverOnMainQueue).start(next: { [weak self] state in
            self?.genericView.updateState(state, animated: !first, arguments: arguments)
            first = false
        }))
        
        disposable.set(historyViewTransition.start(next: { [weak self] transition in
            guard let `self` = self else {return}
            self.tableView.merge(with: transition)
            if !self.didSetReady, !self.tableView.isEmpty {
                self.tableView.scroll(to: .top(id: PeerMediaSharedEntryStableId.messageId(source.messageIndex.id), innerId: nil, animated: false, focus: .init(focus: false), inset: -25))
                self.genericView.setController(self.audioPlayer.controller)
                self.readyOnce()
            }
            switch source {
            case .chat:
                self.tableView.resortController = nil
            case let .profile(peer, _, _, musicContext):
                var range:NSRange = NSMakeRange(NSNotFound, 0)
                var initialIndex = 0
                self.tableView.enumerateItems(with: { item in
                    if item is PeerMediaMusicRowItem {
                        if range.location == NSNotFound {
                            range.location = item.index
                            initialIndex = item.index
                        }
                        range.length += 1
                    }
                    return true
                })
                if range.location != NSNotFound, let reference = PeerReference(peer._asPeer()), peer.id == context.peerId {
                    
                    
                    self.tableView.resortController = .init(resortRange: range, start: { _ in }, resort: { _ in }, complete: { [weak self] from, to in
                        guard let self else {
                            return
                        }
                        
                        let toFile = (self.genericView.tableView.item(at: to) as? PeerMediaMusicRowItem).flatMap {
                            return FileMediaReference.savedMusic(peer: reference, media: $0.file)
                        }
                        let afterFile = (self.genericView.tableView.item(at: to - initialIndex) as? PeerMediaMusicRowItem).flatMap {
                            return FileMediaReference.savedMusic(peer: reference, media: $0.file)
                        }
                        if let toFile {
                            _ = previous.modify { value in
                                var value = value
                                value.move(at: from, to: to)
                                return value
                            }
                            _ = musicContext.addMusic(file: toFile, afterFile: afterFile).start()
                        }
                    })
                } else {
                    self.tableView.resortController = nil
                }
            }
        }))
        
      
        
    }
    
}
