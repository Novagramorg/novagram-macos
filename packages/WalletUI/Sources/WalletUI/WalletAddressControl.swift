import Cocoa
import TGUIKit
import TelegramTheme
import Localization

public final class WalletAddressControl: Control {
    private let addressView = TextView()
    private var copyAddress: (() -> Void)?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addressView.userInteractionEnabled = false
        addressView.isSelectable = false
        addressView.isEventLess = true
        layer?.cornerRadius = 10
        scaleOnClick = true
        setAccessibilityLabel(strings().voiceOverCommonCopy)
        set(handler: { [weak self] _ in
            self?.copyAddress?()
        }, for: .Click)
        addSubview(addressView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(address: String, layout: TextViewLayout, copyAddress: @escaping () -> Void) {
        self.copyAddress = copyAddress
        addressView.update(layout)
        backgroundColor = theme.colors.background
        setAccessibilityValue(address)
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        addressView.center()
    }
}
