import Cocoa
import TGUIKit
import TelegramCore

import TelegramTheme
import AvatarUI
import ShortPeerRow

public class ContextCommandRowItem: TableRowItem {

    fileprivate let _stableId:Int64
    fileprivate let account: Account
    public let command:ChatInputCommand
    
    private let title:TextViewLayout
    private let desc:TextViewLayout
    
    private let titleSelected:TextViewLayout
    private let descSelected:TextViewLayout
    
    public override var stableId: AnyHashable {
        return _stableId
    }
    
    public init(_ initialSize:NSSize, _ account:Account, _ command:ChatInputCommand, _ index:Int64) {
        _stableId = index
        self.command = command
        self.account = account
        title = TextViewLayout(.initialize(string: "/" + command.command.text, color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1, truncationType: .end)
        desc = TextViewLayout(.initialize(string: command.command.description, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1, truncationType: .end)
        
        titleSelected = TextViewLayout(.initialize(string: "/" + command.command.text, color: theme.colors.underSelectedColor, font: .medium(.text)), maximumNumberOfLines: 1, truncationType: .end)
        descSelected = TextViewLayout(.initialize(string: command.command.description, color: theme.colors.underSelectedColor, font: .normal(.text)), maximumNumberOfLines: 1, truncationType: .end)
        super.init(initialSize)
        _ = makeSize(initialSize.width, oldWidth: initialSize.width)
    }
    
    public override var height: CGFloat {
        return 40
    }
    
    public override func viewClass() -> AnyClass {
        return ContextCommandRowView.self
    }

    public override var accessibilityLabel: String? {
        return title.attributedString.string
    }

    public override var accessibilityValue: String? {
        let text = desc.attributedString.string
        return text.isEmpty ? nil : text
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        title.measure(width: width - 60)
        desc.measure(width: width - 60)
        titleSelected.measure(width: width - 60)
        descSelected.measure(width: width - 60)
        return success
    }
    
    var ctxTitle:TextViewLayout {
        return isSelected ? titleSelected : title
    }
    
    var ctxDesc:TextViewLayout {
        return isSelected ? descSelected : desc
    }
    
}



class ContextCommandRowView : TableRowView {
    private let textView:TextView = TextView()
    private let descView:TextView = TextView()
    private let photoView:AvatarControl = AvatarControl(font: .avatar(.title))
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        textView.userInteractionEnabled = false
        descView.userInteractionEnabled = false
        photoView.userInteractionEnabled = false
        addSubview(textView)
        addSubview(descView)
        addSubview(photoView)
        photoView.frame = NSMakeRect(10, 5, 30, 30)
    }
    
    override func layout() {
        super.layout()
        if let item = item as? ContextCommandRowItem {
            textView.update(item.ctxTitle, origin:NSMakePoint(50, floorToScreenPixels(backingScaleFactor, frame.height / 2 - item.ctxTitle.layoutSize.height)))
            descView.update(item.ctxDesc, origin:NSMakePoint(50, floorToScreenPixels(backingScaleFactor, frame.height / 2)))
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var backdorColor: NSColor {
        if let item = item {
            return item.isSelected ? theme.colors.accentSelect : .clear
        } else {
            return .clear
        }
    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated:animated)
        if let item = item as? ContextCommandRowItem {
            photoView.setPeer(account: item.account, peer: item.command.peer._asPeer())
        }
        needsLayout = true
    }
    
}
