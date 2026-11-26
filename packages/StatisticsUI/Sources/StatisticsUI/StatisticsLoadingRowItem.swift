import Cocoa
import TGUIKit
import SwiftSignalKit
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import AvatarUI
import ShortPeerRow
import LocalAnimations
import GraphUI
import DateUtils
import TelegramIconsTheme
import TelegramCore
import Postbox
import TelegramMediaUtils
import MessageTextUtils

public class StatisticsLoadingRowItem: GeneralRowItem {
    
    public let text:TextViewLayout?
    
    public let context: any AccountContextProtocol
    public init(_ initialSize: NSSize, stableId:AnyHashable, context: any AccountContextProtocol, text:String? = nil, viewType: GeneralViewType = .legacy) {
        self.context = context
        if let text = text {
            let attr = NSMutableAttributedString()
            _ = attr.append(string: text, color: theme.colors.grayText, font: .normal(.title))
            attr.detectBoldColorInString(with: .medium(.title))
            self.text = TextViewLayout(attr, alignment: .center)
            self.text?.measure(width: initialSize.width - 60)
        } else {
            self.text = nil
        }
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        text?.measure(width: width - 60)
        return success
    }
    
    public override var instantlyResize: Bool {
        return false
    }

    public override var accessibilityLabel: String? {
        return text?.attributedString.string ?? strings().voiceOverCommonLoading
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    public override var height: CGFloat {
        if let table = table {
            var basic:CGFloat = 0
            table.enumerateItems(with: { [weak self] item in
                if let strongSelf = self {
                    if item.index < strongSelf.index {
                        basic += item.height
                    }
                }
                return true
            })
            return table.frame.height - basic
        } else {
            return initialSize.height
        }
    }
    
    public override func viewClass() -> AnyClass {
        return StatisticsLoadingRowView.self
    }
}


public class StatisticsLoadingRowView : TableRowView {
    private let imageView: StatisticsStickerView = StatisticsHooks.shared.makeStickerView()
    private let textView:TextView = TextView()
    private let disposable = MetaDisposable()
    private let progressIndicator = ProgressIndicator(frame: NSMakeRect(0, 0, 30, 30))
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(progressIndicator)
        addSubview(imageView)
        addSubview(textView)
        textView.isSelectable = false
        
        
        
        self.imageView.change(opacity: 0, animated: false)
        self.textView.change(opacity: 0, animated: false)
        self.progressIndicator.change(opacity: 1, animated: false)
        
        let signal = Signal<NoValue, NoError>.complete() |> delay(1.5, queue: .mainQueue())
        
        disposable.set(signal.start(completed: { [weak self] in
            self?.imageView.change(opacity: 1, animated: true)
            self?.textView.change(opacity: 1, animated: true)
            self?.progressIndicator.change(opacity: 0, animated: true)
        }))
    }
    
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func updateColors() {
        super.updateColors()
        textView.backgroundColor = backdorColor
        progressIndicator.progressColor = theme.colors.text
    }
    
    public override func layout() {
        super.layout()
        
        progressIndicator.center()
        
        if let item = item as? StatisticsLoadingRowItem {
            textView.update(item.text)
            textView.centerX(y: frame.midY + 5)
            imageView.centerX(y: frame.midY - imageView.frame.height - 5)
        } else {
            imageView.center()
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        disposable.dispose()
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item)
        
        if let item = item as? StatisticsLoadingRowItem {
            
            imageView.updateSticker(animation: LocalAnimatedSticker.graph_loading, size: NSMakeSize(80, 80), context: item.context, table: item.table, animated: animated)
            
            self.needsLayout = true
            
            
        }
    }
}
