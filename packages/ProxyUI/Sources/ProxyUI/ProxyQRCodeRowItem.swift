import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import MtProtoKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import GeneralRows
import InputDataUI
import AlertsUI
import ProxyUtils
import QRCodeUtils

class ProxyQRCodeRowItem: GeneralRowItem {

    let link: String
    

    fileprivate let textLayout: TextViewLayout
    
    init(_ initialSize: NSSize, stableId: AnyHashable, link: String) {
        self.link = link
        textLayout = TextViewLayout(.initialize(string: strings().proxySettingsQRText, color: theme.colors.grayText, font: .normal(.text)), alignment: .center, alwaysStaticItems: true)
        textLayout.measure(width: 256)
        super.init(initialSize, stableId: stableId, viewType: .singleItem)
    }

    
    
    override var height: CGFloat {
        return 256.0 + textLayout.layoutSize.height + 30
    }
    
    override func viewClass() -> AnyClass {
        return ProxyQRCodeRowView.self
    }

    override var accessibilityLabel: String? {
        return textLayout.attributedString.string
    }
}


private final class ProxyQRCodeRowView : TableRowView {
    private let disposable = MetaDisposable()
    private let imageView: ImageView = ImageView(frame: NSMakeRect(0, 0, 256, 256))
    private let textView: TextView = TextView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        addSubview(textView)
        imageView.setAccessibilityLabel(strings().voiceOverCommonQRCode)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var backdorColor: NSColor {
        guard let item = item as? ProxyQRCodeRowItem else { return theme.colors.background }
        return item.viewType.rowBackground
    }
    
    override func layout() {
        super.layout()
        textView.centerX(y: 10)
        imageView.centerX(y: textView.frame.maxY + 10)
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        
        guard let item = item as? ProxyQRCodeRowItem else { return }
        
        textView.update(item.textLayout)
        
        disposable.set((qrCode(string: item.link, color: theme.colors.text, backgroundColor: theme.colors.grayBackground, icon: .proxy)
            |> map { generator -> CGImage? in
                let imageSize = CGSize(width: 256, height: 256)
                let context = generator.1(TransformImageArguments(corners: ImageCorners(), imageSize: imageSize, boundingSize: imageSize, intrinsicInsets: NSEdgeInsets()))
                
                return context?.generateImage()
            }
            |> deliverOnMainQueue).start(next: { [weak self] image in
                if let image = image {
                    self?.imageView.image = image
                }
            }))
        
        needsLayout = true
    }
    
    deinit {
        disposable.dispose()
    }
}
