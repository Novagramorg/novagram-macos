import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import DateUtils
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import ShortPeerRow
import AvatarUI
import TelegramMediaUtils
import AlertsUI
import LocalAnimations
import MessageTextUtils

public final class CommunityInfoRowItem: GeneralRowItem {

    public let context: (any AccountContextProtocol)
    public let communityId: PeerId

    public private(set) var peer: Peer?
    public private(set) var chatCount: Int32 = 0

    public private(set) var titleLayout: TextViewLayout
    public private(set) var subtitleLayout: TextViewLayout

    private let disposable = MetaDisposable()

    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), communityId: PeerId, viewType: GeneralViewType, action: @escaping () -> Void) {
        self.context = context
        self.communityId = communityId

        titleLayout = TextViewLayout(.initialize(string: strings().communityInfoCommunity, color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1)
        subtitleLayout = TextViewLayout(.initialize(string: strings().communityInfoCommunity, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)

        super.init(initialSize, stableId: stableId, viewType: viewType, action: action)

        context.account.viewTracker.forceUpdateCachedPeerData(peerId: communityId)

        let peerSignal = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: communityId))
        let cachedSignal = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.CachedData(id: communityId))

        disposable.set((combineLatest(peerSignal, cachedSignal) |> deliverOnMainQueue).start(next: { [weak self] enginePeer, cachedData in
            guard let self else { return }
            self.peer = enginePeer?._asPeer()
            self.chatCount = Int32((cachedData as? CachedCommunityData)?.linkedPeers.count ?? 0)
            self.rebuildLayouts()
            self.redraw(animated: true)
        }))
    }

    private func rebuildLayouts() {
        let titleText = peer?.displayTitle ?? strings().communityInfoCommunity
        titleLayout = TextViewLayout(.initialize(string: titleText, color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1)

        let subtitleText: String
        if peer != nil {
            let n = chatCount
            subtitleText = strings().communityInfoCommunityWithChatsOther(Int(n))
        } else {
            subtitleText = strings().communityInfoCommunity
        }
        subtitleLayout = TextViewLayout(.initialize(string: subtitleText, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)

        measureLayouts()
    }

    private func measureLayouts() {
        let avatarWidth: CGFloat = 36
        let leftPad: CGFloat = viewType.innerInset.left + avatarWidth + 10
        let rightPad: CGFloat = viewType.innerInset.right + 20 + 10
        let availableWidth = blockWidth - leftPad - rightPad
        titleLayout.measure(width: availableWidth)
        subtitleLayout.measure(width: availableWidth)
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        measureLayouts()
        return result
    }

    public override var height: CGFloat {
        return 50
    }

    public override func viewClass() -> AnyClass {
        return CommunityInfoRowView.self
    }

    public override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return subtitleLayout.attributedString.string
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }

    deinit {
        disposable.dispose()
    }
}

public final class CommunityInfoRowView: GeneralContainableRowView {

    private let avatar = AvatarControl(font: .avatar(14))
    private let titleView = TextView()
    private let subtitleView = TextView()
    private let chevron = ImageView()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        avatar.setFrameSize(NSMakeSize(36, 36))
        avatar.userInteractionEnabled = false

        titleView.userInteractionEnabled = false
        titleView.isSelectable = false

        subtitleView.userInteractionEnabled = false
        subtitleView.isSelectable = false

        chevron.isEventLess = true
        chevron.isAccessibilityDecorative = true

        addSubview(avatar)
        addSubview(titleView)
        addSubview(subtitleView)
        addSubview(chevron)

        containerView.set(handler: { [weak self] _ in
            if let item = self?.item as? GeneralRowItem {
                item.action()
            }
        }, for: .Click)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? CommunityInfoRowItem else { return }

        avatar.setPeer(account: item.context.account, peer: item.peer)

        titleView.update(item.titleLayout)
        subtitleView.update(item.subtitleLayout)

        chevron.image = theme.icons.generalNext
        chevron.sizeToFit()

        needsLayout = true
    }

    public override func layout() {
        super.layout()

        guard let item = item as? CommunityInfoRowItem else { return }

        let leftInset = item.viewType.innerInset.left
        let containerHeight = containerView.frame.height

        avatar.centerY(x: leftInset)

        let textX = avatar.frame.maxX + 10

        let totalTextHeight = titleView.frame.height + 2 + subtitleView.frame.height
        let textY = floorToScreenPixels(backingScaleFactor, (containerHeight - totalTextHeight) / 2)

        titleView.setFrameOrigin(NSMakePoint(textX, textY))
        subtitleView.setFrameOrigin(NSMakePoint(textX, titleView.frame.maxY + 2))

        chevron.centerY(x: containerView.frame.width - chevron.frame.width - item.viewType.innerInset.right)
    }
}
