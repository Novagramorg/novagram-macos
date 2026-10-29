import AppKit
import TGUIKit
import SwiftSignalKit

public struct NovagramCallExtrasHooks {
    public var showDeviceMenu: (_ view: NSView, _ event: NSEvent) -> Void = { _, _ in }
    public var isWeakNetworkBannerEnabled: () -> Bool = { false }
    public var weakConnectionText: () -> String = { "" }
    public var turnOffVideoText: () -> String = { "" }

    public init() {}

    public static var shared = NovagramCallExtrasHooks()

    public static func install(_ hooks: NovagramCallExtrasHooks) {
        shared = hooks
    }
}

func novagramShowCallDeviceMenu(_ view: NSView) {
    guard let event = NSApp.currentEvent else {
        return
    }
    NovagramCallExtrasHooks.shared.showDeviceMenu(view, event)
}

final class NovagramCallWeakNetwork {
    static let shared = NovagramCallWeakNetwork()

    private static let lowReception: Int32 = 1
    private static let showDelay: Double = 5

    private weak var window: Window?
    private var banner: NovagramCallWeakNetworkBanner?
    private var turnOffVideo: (() -> Void)?
    private var canTurnOffVideo = false
    private var isWeak = false
    private let delayDisposable = MetaDisposable()

    func update(window: Window, external: ExternalPeerCallState, turnOffVideo: @escaping () -> Void) {
        if let current = self.window, current !== window {
            reset()
        }
        self.window = window
        self.turnOffVideo = turnOffVideo
        canTurnOffVideo = NovagramCallWeakNetwork.isOwnVideoOn(external)
        let weak = NovagramCallExtrasHooks.shared.isWeakNetworkBannerEnabled() && NovagramCallWeakNetwork.isWeak(external)
        if weak != isWeak {
            isWeak = weak
            if weak {
                delayDisposable.set((Signal<Void, NoError>.single(Void()) |> delay(NovagramCallWeakNetwork.showDelay, queue: .mainQueue())).start(next: { [weak self] in
                    self?.showBanner()
                }))
            } else {
                reset()
            }
        }
        banner?.update(canTurnOffVideo: canTurnOffVideo)
        if let banner, let content = window.contentView, banner.superview !== content {
            banner.place(in: content)
        }
    }

    private func showBanner() {
        guard isWeak, banner == nil, let content = window?.contentView else {
            return
        }
        let banner = NovagramCallWeakNetworkBanner(text: NovagramCallExtrasHooks.shared.weakConnectionText(), buttonTitle: NovagramCallExtrasHooks.shared.turnOffVideoText())
        banner.onTurnOffVideo = { [weak self] in
            self?.turnOffVideo?()
        }
        banner.update(canTurnOffVideo: canTurnOffVideo)
        banner.place(in: content)
        self.banner = banner
    }

    private func reset() {
        delayDisposable.set(nil)
        isWeak = false
        banner?.removeFromSuperview()
        banner = nil
    }

    private static func isWeak(_ external: ExternalPeerCallState) -> Bool {
        guard !external.canBeRemoved else {
            return false
        }
        switch external.state {
        case let .active(_, reception, _):
            if let reception {
                return reception <= lowReception
            }
            return false
        case .reconnecting:
            return true
        default:
            return false
        }
    }

    private static func isOwnVideoOn(_ external: ExternalPeerCallState) -> Bool {
        guard case .active = external.videoState else {
            return false
        }
        return !external.isOutgoingVideoPaused && !external.isScreenCapture
    }
}

final class NovagramCallWeakNetworkBanner: NSView {
    private static let height: CGFloat = 30
    private static let topInset: CGFloat = 48
    private static let padding: CGFloat = 12
    private static let spacing: CGFloat = 10
    private static let fontSize: CGFloat = 13
    private static let zPosition: CGFloat = 1000
    private static let backgroundAlpha: CGFloat = 0.6

    var onTurnOffVideo: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let button = NSButton(title: "", target: nil, action: nil)

    init(text: String, buttonTitle: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(NovagramCallWeakNetworkBanner.backgroundAlpha).cgColor
        layer?.cornerRadius = NovagramCallWeakNetworkBanner.height / 2
        layer?.zPosition = NovagramCallWeakNetworkBanner.zPosition
        label.stringValue = text
        label.font = .systemFont(ofSize: NovagramCallWeakNetworkBanner.fontSize, weight: .medium)
        label.textColor = .white
        button.isBordered = false
        button.attributedTitle = NSAttributedString(string: buttonTitle, attributes: [
            .font: NSFont.systemFont(ofSize: NovagramCallWeakNetworkBanner.fontSize, weight: .semibold),
            .foregroundColor: NSColor.systemYellow
        ])
        button.target = self
        button.action = #selector(turnOffVideo)
        addSubview(label)
        addSubview(button)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var mouseDownCanMoveWindow: Bool {
        return false
    }

    @objc private func turnOffVideo() {
        onTurnOffVideo?()
    }

    func update(canTurnOffVideo: Bool) {
        guard button.isHidden == canTurnOffVideo else {
            return
        }
        button.isHidden = !canTurnOffVideo
        if let content = superview {
            layout(in: content)
        }
    }

    func place(in content: NSView) {
        content.addSubview(self)
        layout(in: content)
    }

    private func layout(in content: NSView) {
        label.sizeToFit()
        button.sizeToFit()
        let buttonWidth = button.isHidden ? 0 : NovagramCallWeakNetworkBanner.spacing + ceil(button.frame.width)
        let size = NSSize(width: NovagramCallWeakNetworkBanner.padding * 2 + ceil(label.frame.width) + buttonWidth, height: NovagramCallWeakNetworkBanner.height)
        let x = floor((content.bounds.width - size.width) / 2)
        let y = content.isFlipped ? NovagramCallWeakNetworkBanner.topInset : content.bounds.height - NovagramCallWeakNetworkBanner.topInset - size.height
        frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
        autoresizingMask = content.isFlipped ? [.minXMargin, .maxXMargin, .maxYMargin] : [.minXMargin, .maxXMargin, .minYMargin]
        label.frame = NSRect(x: NovagramCallWeakNetworkBanner.padding, y: floor((size.height - label.frame.height) / 2), width: ceil(label.frame.width), height: label.frame.height)
        button.frame = NSRect(x: label.frame.maxX + NovagramCallWeakNetworkBanner.spacing, y: floor((size.height - button.frame.height) / 2), width: ceil(button.frame.width), height: button.frame.height)
    }
}
