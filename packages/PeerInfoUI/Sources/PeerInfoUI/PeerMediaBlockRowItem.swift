import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import CoreGraphics
import TelegramContext
import GeneralRows
import Localization

class PeerMediaBlockRowItem<Context: AccountContextProtocol>: GeneralRowItem {
    
    fileprivate var temporaryHeight: CGFloat?
    fileprivate let listener: TableScrollListener
    fileprivate let controller: PeerMediaController<Context>
    fileprivate let isMediaVisible: Bool
    init(_ initialSize: NSSize, stableId: AnyHashable, controller: PeerMediaController<Context>, isVisible: Bool, viewType: GeneralViewType) {
        self.controller = controller
        self.isMediaVisible = isVisible
        self.listener = TableScrollListener(dispatchWhenVisibleRangeUpdated: false, { _ in })
        super.init(initialSize, height: initialSize.height, stableId: stableId, viewType: viewType, inset: NSEdgeInsets())
    }
    
    deinit {
        if self.controller.isLoaded(), let table = self.table {
//            let view = self.controller.genericView
//            view.removeFromSuperview()
            
            if controller.frame.minY == 0 {
                table.scroll(to: .up(true))
                if self.controller.genericView.superview != nil {
                    controller.setProfileBlockVisible(false)
                    self.controller.genericView.removeFromSuperview()
                }
            }
        }
        
    }
    
    override var instantlyResize: Bool {
        return false
    }
    
    override var height: CGFloat {
     //   return 10000
        
        if !isMediaVisible {
            return 1
        } else {
            if let temporaryHeight = temporaryHeight {
                return temporaryHeight
            } else {
                return (table?.frame.height ?? initialSize.height) - 64
            }
        }
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        return true
    }
    
    override var accessibilityLabel: String? {
        return isMediaVisible ? strings().peerInfoSharedMedia : nil
    }
    
    override var accessibilityIsSpacer: Bool {
        return !isMediaVisible
    }
    
    override func viewClass() -> AnyClass {
        return PeerMediaBlockRowView<Context>.self
    }
}


private final class PeerMediaBlockRowView<Context: AccountContextProtocol> : TableRowView {
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    private func updateOrigin() {
        guard let item = item as? PeerMediaBlockRowItem<Context>, let table = item.table else {
            return
        }
                
        item.controller.view.frame = NSMakeRect(0, max(0, table.rectOf(item: item).minY), self.frame.width, item.height)
    }
    
    override func layout() {
        super.layout()
        updateOrigin()
    }
    
    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        updateOrigin()
    }
    
    override func removeFromSuperview() {
        super.removeFromSuperview() 
    }
    
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        
        guard let item = item as? PeerMediaBlockRowItem<Context> else {
            return
        }
        
        if item.controller.view != item.table?.documentView?.subviews.last {
            item.controller.view.removeFromSuperview()
            item.table?.documentView?.addSubview(item.controller.view)
        }
    }
    
    override func scrollWheel(with event: NSEvent) {
        guard let item = item as? PeerMediaBlockRowItem<Context> else {
            super.scrollWheel(with: event)
            return
        }
        item.controller.view.enclosingScrollView?.scrollWheel(with: event)
    }
    
    private var scrollInner = false
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? PeerMediaBlockRowItem<Context> else {
            return
        }
        
        item.table?.updatedItems = { [weak self] _ in
            self?.updateOrigin()
        }
                
        let mediaView = item.controller.view
        item.table?.documentSubviewKeptAboveRows = { [weak mediaView] view in
            return view === mediaView
        }

        item.controller.bar = .init(height: 0)
        item.controller._frameRect = bounds
        item.controller.genericView.headerOverflow = 64
       
        
        var scrollingInMediaTable: Bool = false
        
        
        if item.isMediaVisible {
            
            item.listener.handler = { [weak self, weak item] _ in
                guard let `self` = self, let table = item?.table, let item = item else {
                    return
                }
                
                guard let item = table.item(stableId: item.stableId) as? PeerMediaBlockRowItem<Context> else {
                    return
                }
                
                let itemY = table.rectOf(item: item).minY
                let offsetY = table.liveDocumentOffset.y

                scrollInner = offsetY + 64 >= itemY
                let mediaTable = item.controller.genericView.mainTable
                if let mediaTable = mediaTable {
                    
                    let offset = offsetY + 64 - itemY
                    var updated = max(0, offset)
                    if mediaTable.documentSize.height <= item.height, updated > 0 {
                        updated = max(updated, 0)
                    }
                    let topInset = mediaTable.contentInsets.top
                    if !scrollingInMediaTable, updated - topInset != mediaTable.liveDocumentOffset.y {
                        mediaTable.clipView.scroll(to: NSMakePoint(0, updated - topInset))
                        mediaTable.reflectScrolledClipView(mediaTable.clipView)
                    }
                    if scrollInner {
                        
                    } else {
                        if mediaTable.liveDocumentOffset.y > -topInset {
                            scrollInner = true
                        }
                    }
                    NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: mediaTable.clipView)
                    

                    
                    item.controller.view.frame = NSMakeRect(0, max(0, itemY), self.frame.width, item.height)
                    
                    let point = item.controller.view.frame.origin

                    item.controller.setProfileBlockVisible(offsetY + 64 >= point.y)
                }
            }
            
            item.table?.addScroll(listener: item.listener)
            
            item.table?.hasVerticalScroller = false
            
            item.table?._scrollWillStartLiveScrolling = {
                scrollingInMediaTable = false
            }
            item.controller.genericView.mainTable?.reloadData()
        } else {
            needsLayout = true
        }
        
        if item.controller.view != item.table?.documentView?.subviews.last {
            item.controller.view.removeFromSuperview()
            item.table?.documentView?.addSubview(item.controller.view)
        }
        if let table = item.table {
            item.controller.genericView.change(pos: NSMakePoint(0, max(0, table.rectOf(item: item).minY)), animated: animated)
        }
        
        if item.isMediaVisible {
            item.controller.genericView.isHidden = false
        }
        
        item.controller.genericView.change(opacity: item.isMediaVisible ? 1 : 0, animated: animated, completion: { [weak item] _ in
            guard let item = item else {
                return
            }
            item.controller.genericView.isHidden = !item.isMediaVisible
        })
        
        if item.isMediaVisible {
            item.controller.currentMainTableView = { [weak item, weak self] mainTable, animated, updated in
                
                mainTable?.verticalScrollElasticity = .none
                
                if let item = item, animated {
                    let frame = item.table?.rectOf(item: item) ?? .zero
                    if item.table?.liveDocumentOffset.y == frame.minY {
                        if !updated {
                            mainTable?.scroll(to: .upOffset(true, 0))
                        }
                    } else if updated {
                        DispatchQueue.main.async {
                            item.table?.scroll(to: .top(id: item.stableId, innerId: nil, animated: animated, focus: .init(focus: false), inset: 64))
                        }
                    }
                }
                
                mainTable?.applyExternalScroll = { [weak self, weak item] event in
                    guard let `self` = self, let item = item else {
                        return false
                    }
                    if scrollInner {
                        if event.scrollingDeltaY > 0 {
                            if let tableView = item.controller.genericView.mainTable, tableView.liveDocumentOffset.y <= -tableView.contentInsets.top {
                                if !item.controller.unableToHide {
                                    scrollInner = false
                                    item.table?.clipView.scroll(to: NSMakePoint(0, self.frame.minY - 64 ))
                                    item.table?.scrollWheel(with: event)
                                    scrollingInMediaTable = false
                                    return true
                                }
                                
                            }
                        }
                        scrollingInMediaTable = true
                        return false
                    } else {
                        scrollingInMediaTable = false
                        item.table?.scrollWheel(with: event)
                        return true
                    }
                }
            }
        } else {
            item.controller.currentMainTableView = nil
        }
        
        updateOrigin()
    }

    deinit {
    }
}
