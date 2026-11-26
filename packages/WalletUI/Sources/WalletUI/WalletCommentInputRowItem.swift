import Cocoa
import TGUIKit
import InputDataUI
import GeneralRows
import TelegramMedia
import TelegramTheme

private let walletCommentLockSize: CGFloat = 24
private let walletCommentLockOpenFrame: Int32 = 10
private let walletCommentLockClosedFrame: Int32 = 29

private func walletCommentLockBlankImage() -> CGImage {
    return generateImage(NSMakeSize(walletCommentLockSize, walletCommentLockSize), contextGenerator: { size, ctx in
        ctx.clear(size.bounds)
    })!
}

final class WalletCommentInputRowItem: InputDataRowItem {
    fileprivate let commentEncrypted: Bool
    fileprivate let lockEnabled: Bool
    fileprivate let lockDescription: String
    fileprivate let toggleEncryption: () -> Void
    private let placeholderText: String

    init(_ initialSize: NSSize, stableId: AnyHashable, viewType: GeneralViewType, currentText: String, inputPlaceholder: String, commentEncrypted: Bool, lockEnabled: Bool, lockDescription: String, limit: Int32, updated: @escaping (String) -> Void, toggleEncryption: @escaping () -> Void) {
        self.commentEncrypted = commentEncrypted
        self.lockEnabled = lockEnabled
        self.lockDescription = lockDescription
        self.toggleEncryption = toggleEncryption
        self.placeholderText = inputPlaceholder
        super.init(initialSize, stableId: stableId, mode: .plain, error: nil, viewType: viewType, currentText: currentText, placeholder: nil, inputPlaceholder: inputPlaceholder, rightItem: .action(walletCommentLockBlankImage(), .none), filter: walletCommentInputFilter, updated: updated, limit: limit, customTheme: GeneralRowItem.Theme(backgroundColor: theme.colors.grayBackground))
    }

    override func viewClass() -> AnyClass {
        return WalletCommentInputRowView.self
    }

    override var accessibilityLabel: String? {
        return placeholderText.isEmpty ? nil : placeholderText
    }
}

private final class WalletCommentInputRowView: InputDataRowView {
    private let lockControl = Control(frame: NSMakeRect(0, 0, walletCommentLockSize + 8, walletCommentLockSize + 8))
    private let lockPlayer = LottiePlayerView(frame: NSMakeRect(0, 0, walletCommentLockSize, walletCommentLockSize))
    private var displayedEncrypted: Bool?
    private var displayedColor: NSColor?
    private var lockData: Data?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        lockPlayer.isEventLess = true
        lockControl.scaleOnClick = true
        lockControl.addSubview(lockPlayer)
        lockControl.set(handler: { [weak self] _ in
            (self?.item as? WalletCommentInputRowItem)?.toggleEncryption()
        }, for: .Click)
        containerView.addSubview(lockControl)
        if let url = Bundle.module.url(forResource: "WalletCommentLock", withExtension: "tgs") {
            lockData = try? Data(contentsOf: url)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func lockAnimation(playPolicy: LottiePlayPolicy, color: NSColor) -> LottieAnimation? {
        guard let lockData else {
            return nil
        }
        return LottieAnimation(compressed: lockData, key: LottieAnimationEntryKey(key: .bundle("WalletCommentLock"), size: NSMakeSize(walletCommentLockSize, walletCommentLockSize)), cachePurpose: .none, playPolicy: playPolicy, maximumFps: 60, colors: [LottieColor(keyPath: "", color: color)])
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletCommentInputRowItem else {
            return
        }
        let color = item.commentEncrypted ? walletClassicAccent : theme.colors.grayIcon
        lockControl.userInteractionEnabled = item.lockEnabled
        lockControl.isEnabled = item.lockEnabled
        lockControl.toolTip = item.lockDescription
        lockPlayer.layer?.opacity = item.lockEnabled ? 1.0 : 0.5
        if let displayedEncrypted, displayedEncrypted != item.commentEncrypted, window != nil {
            let range: ClosedRange<Int32> = item.commentEncrypted ? walletCommentLockOpenFrame ... walletCommentLockClosedFrame : 0 ... walletCommentLockOpenFrame
            lockPlayer.set(lockAnimation(playPolicy: .loopAt(firstStart: range.lowerBound, range: range), color: color), reset: true, saveContext: false, animated: false)
        } else if displayedEncrypted != item.commentEncrypted || displayedColor != color {
            let frame = item.commentEncrypted ? walletCommentLockClosedFrame : walletCommentLockOpenFrame
            lockPlayer.set(lockAnimation(playPolicy: .loopAt(firstStart: frame, range: (frame - 1) ... frame), color: color), reset: true, saveContext: false, animated: false)
        }
        displayedEncrypted = item.commentEncrypted
        displayedColor = color
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletCommentInputRowItem else {
            return
        }
        let innerInsets = item.viewType.innerInset
        let x = containerView.frame.width - innerInsets.right - walletCommentLockSize - 4
        let y: CGFloat
        if containerView.frame.height <= 44 {
            y = floorToScreenPixels(backingScaleFactor, (containerView.frame.height - lockControl.frame.height) / 2)
        } else {
            y = max(0, innerInsets.top - 6)
        }
        lockControl.setFrameOrigin(NSMakePoint(x, y))
        lockPlayer.center()
    }
}
