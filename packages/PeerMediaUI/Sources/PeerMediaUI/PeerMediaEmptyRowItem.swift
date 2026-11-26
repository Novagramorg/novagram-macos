import Cocoa
import TGUIKit
import Postbox
import Localization
import TelegramTheme



public class PeerMediaEmptyRowItem: TableRowItem {
    public let textLayout:TextViewLayout
    public let tags:MessageTags?
    public let image:CGImage
    public init(_ initialSize:NSSize, tags:MessageTags?) {
        self.tags = tags
        let attr:NSAttributedString
        if let tags = tags {
            if tags.contains(.file) {
                image = theme.icons.mediaEmptyFiles
                attr = .initialize(string: strings().peerMediaSharedFilesEmptyList1, color: theme.colors.grayText, font: .normal(.header))
            } else if tags.contains(.music) || tags.contains(.voiceOrInstantVideo) {
                image = theme.icons.mediaEmptyMusic
                attr = .initialize(string: tags.contains(.voiceOrInstantVideo) ? strings().peerMediaSharedVoiceEmptyList : strings().peerMediaSharedMusicEmptyList, color: theme.colors.grayText, font: .normal(.header))
            } else if tags.contains(.webPage) {
                image = theme.icons.mediaEmptyLinks
                attr = .initialize(string: strings().peerMediaSharedLinksEmptyList, color: theme.colors.grayText, font: .normal(.header))
            } else {
                image = theme.icons.mediaEmptyShared
                attr = .initialize(string: strings().peerMediaSharedMediaEmptyList, color: theme.colors.grayText, font: .normal(.header))
            }
        } else {
            image = theme.icons.mediaEmptyShared
            attr = .initialize(string: strings().peerMediaShareMediaSavedMessages, color: theme.colors.grayText, font: .normal(.header))
        }
        
        textLayout = TextViewLayout(attr, alignment: .center)
        super.init(initialSize)
    }
    
    public override var height: CGFloat {
        if let table = table {
            return table.frame.height
        } else {
            return initialSize.height
        }
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        return true
    }
    
    public override func viewClass() -> AnyClass {
        return PeerMediaEmptyRowView.self
    }

    public override var accessibilityLabel: String? {
        return textLayout.attributedString.string
    }
}

public class PeerMediaEmptyRowView : TableRowView {
    private let textView:TextView = TextView()
    private let imageView:ImageView = ImageView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        textView.isSelectable = false
        addSubview(imageView)
        imageView.isAccessibilityDecorative = true
    }
    
    public override var backdorColor: NSColor {
        return theme.colors.listBackground
    }
    
    public override func updateColors() {
        super.updateColors()
        textView.backgroundColor = backdorColor
    }
    
    public override func layout() {
        super.layout()
        if let item = item as? PeerMediaEmptyRowItem {
            imageView.centerX(y: bounds.midY - imageView.frame.height)
            item.textLayout.measure(width: frame.width - 60)
            textView.update(item.textLayout)
            textView.centerX(y: imageView.frame.maxY + 16)
        }
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        if let item = item as? PeerMediaEmptyRowItem {
            imageView.image = item.image
            imageView.sizeToFit()
            needsLayout = true
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
