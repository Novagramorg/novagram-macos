import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import SwiftSignalKit
import CurrencyFormat
import InAppSettings
import TelegramMediaUtils
import TelegramTheme
import Localization
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI

public final class PaymentsTipsRowItem : GeneralRowItem {
    
    public struct Tip {
        fileprivate var text: TextViewLayout
        fileprivate var value: Int64
        fileprivate var size: NSSize
    }
    
    fileprivate let tips:BotPaymentInvoice.Tip
    fileprivate let current: Int64?
    fileprivate let currency: String
    public private(set) var rendered: [[Tip]] = []
    public let layouts: [(TextViewLayout, Int64)]
    public let select:(Int64?)->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, viewType: GeneralViewType, currency: String, tips: BotPaymentInvoice.Tip, current: Int64?, select: @escaping(Int64?)->Void) {
        self.tips = tips
        self.current = current
        self.currency = currency
        self.select = select
        var layouts:[(TextViewLayout, Int64)] = []
        
        for amount in tips.suggested {
            
            let layout = TextViewLayout(.initialize(string: formatCurrencyAmount(amount, currency: self.currency), color: current == amount ? .white : theme.colors.greenUI, font: .medium(.text)))
            layout.measure(width: .greatestFiniteMagnitude)
            layouts.append((layout, amount))
        }
        
        self.layouts = layouts
        
        super.init(initialSize, stableId: stableId, viewType: viewType)
        
        _ = makeSize(initialSize.width, oldWidth: 0)
    }
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        let width = self.blockWidth - viewType.innerInset.left - viewType.innerInset.right
                
        var rendered:[[Tip]] = []
        
        let insets: NSEdgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        let insetBetween = NSEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        
        
        var row:[Tip] = []
        
        let layoutRow:()->Void = {
            if !row.isEmpty {
                let w = (width - row.reduce(0, { $0 + $1.size.width }) - (insetBetween.right * CGFloat(row.count - 1)))
                
                if w > 0 {
                    let rest = w / CGFloat(row.count)
                    for i in 0 ..< row.count {
                        row[i].size.width += floor(rest)
                    }
                }
                rendered.append(row)
                row.removeAll()
            }
        }

        
        for tip in layouts {
            let minSize = NSMakeSize(tip.0.layoutSize.width + insets.left + insets.right, tip.0.layoutSize.height + insets.bottom + insets.top)
            
            let tip = Tip(text: tip.0, value: tip.1, size: minSize)
            
            var i: Int = 0
            
            row.append(tip)
            
            let row_w: CGFloat = row.reduce(0, { current, value in
                var current = current
                current += tip.size.width + insetBetween.right
                if i == row.count - 1 {
                    current -= insetBetween.right
                }
                i += 1
                return current
            })
            if row_w > width {
                row.removeLast()
                layoutRow()
                row.append(tip)
            }
        }
        layoutRow()
        
        self.rendered = rendered
        
        return true
    }
    
    public override var height: CGFloat {
        return rendered.reduce(0, { current, value in
            let height = value.max(by: { $0.size.height < $1.size.height})!.size.height
            if current == viewType.innerInset.top || rendered.count == 1 {
                return current + height
            } else {
                return current + height + viewType.innerInset.top
            }
        })
    }
    
    public var frames:[NSRect] {
        var x: CGFloat = viewType.innerInset.left
        var y: CGFloat = 0
        var rects:[NSRect] = []
        for row in rendered {
            for col in row {
                let rect = NSMakeRect(x, y, col.size.width, col.size.height)
                rects.append(rect)
                x += rect.width + 5
            }
            x = viewType.innerInset.left
            y += rects.last!.height + viewType.innerInset.top
        }
        return rects
    }
    
    public var count: Int {
        return rendered.reduce(0, { current, value in
            return current + value.count
        })
    }
    
    public var list: [Tip] {
        return rendered.reduce([], { current, value in
            return current + value
        })
    }
    
    public override var hasBorder: Bool {
        return false
    }
    
    public override func viewClass() -> AnyClass {
        return PaymentsTipRowView.self
    }

    public override var accessibilityLabel: String? {
        return strings().paymentsTipLabel
    }

    public override var accessibilityValue: String? {
        return layouts.first(where: { $0.1 == current })?.0.attributedString.string
    }
}

private final class PaymentsTipView : Control {
    private let textView = TextView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.cornerRadius = .cornerRadius
        addSubview(textView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
    }
    
    public func update(_ text: PaymentsTipsRowItem.Tip, selected: Bool, animated: Bool, select: @escaping(Int64?)->Void) {
        backgroundColor = selected ? theme.colors.greenUI : theme.colors.greenUI.withAlphaComponent(0.4)
        if animated {
            layer?.animateBackground()
        }
        textView.update(text.text)
        setAccessibilityLabel(selected ? "\(text.text.attributedString.string), \(strings().voiceOverCommonSelected)" : text.text.attributedString.string)
        
        self.removeAllHandlers()
        self.set(handler: { _ in
            if selected {
                select(nil)
            } else {
                select(text.value)
            }
        }, for: .Click)
        
        textView.center()
    }
    public override func layout() {
        super.layout()
        textView.center()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


private final class PaymentsTipRowView : GeneralContainableRowView {
    private var contentView:[WeakReference<PaymentsTipView>] = []
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        
        guard let item = item as? PaymentsTipsRowItem else {
            return
        }
        for (i, frame) in item.frames.enumerated() {
            let view = contentView[i].value
            view?.frame = frame
        }
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? PaymentsTipsRowItem else {
            return
        }
        
        while contentView.count > item.count {
            contentView.last?.value?.removeFromSuperview()
            contentView.removeLast()
        }
        while contentView.count < item.count {
            let view = PaymentsTipView(frame: .zero)
            addSubview(view)
            contentView.append(WeakReference(value: view))
        }
        
        for (i, frame) in item.frames.enumerated() {
            let view = contentView[i].value
            view?.frame = frame
            view?.update(item.list[i], selected: item.current == item.list[i].value, animated: animated, select: item.select)
        }
    }
}
