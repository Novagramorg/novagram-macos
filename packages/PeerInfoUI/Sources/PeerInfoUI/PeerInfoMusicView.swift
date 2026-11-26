import Cocoa
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramTheme
import TelegramContext


public final class PeerInfoMusicView : View {
    public static func height(colorful: Bool) -> CGFloat {
        return colorful ? 24 : 20
    }
    private let textView: TextView = TextView()
    private var titleFont: NSFont = .semibold(.short)
    private let chevron = ImageView()
    private let imageView = ImageView()
    private let container = View()
    public let control = Control()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(control)
        control.addSubview(container)
        container.addSubview(textView)
        container.addSubview(chevron)
        container.addSubview(imageView)

        textView.userInteractionEnabled = false
        textView.isSelectable = false
        textView.isAccessibilityDecorative = true
        chevron.isAccessibilityDecorative = true
        imageView.isAccessibilityDecorative = true
        
        control.scaleOnClick = true
        
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(file: TelegramMediaFile, primaryText: NSColor, secondaryText: NSColor, backgroundColor: NSColor, colorfull: Bool, context: any AccountContextProtocol) {
        var t:String = "Unknown Track"
        var p:String = "Unknown Performer"
        
        
        

        
        self.backgroundColor = colorfull ? backgroundColor : .clear
        
        for attribute in file.attributes {
            if case let .Audio(_, _, title, performer, _) = attribute {
                if let title {
                    t = title
                }
                if let performer {
                    p = performer
                }
                break
            }
        }
        
        titleFont = !colorfull ? .semibold(.text) : .semibold(.short)
        let attr = NSMutableAttributedString()
        attr.append(string: t, color: primaryText, font: titleFont)
        attr.append(string: " - ", color: secondaryText, font: !colorfull ? .normal(.text) : .normal(.short))
        attr.append(string: p, color: secondaryText, font: !colorfull ? .normal(.text) : .normal(.short))

        let textLayout = TextViewLayout(attr, maximumNumberOfLines: 1, alignment: .center)
        textLayout.measure(width: frame.width - 40)
        
        self.textView.update(textLayout)
        control.setAccessibilityLabel(attr.string)
        
        imageView.image = TelegramThemeHooks.shared.image(.iconPeerMusicWaveform).precomposed(primaryText)
        imageView.sizeToFit()

        
        chevron.image = TelegramThemeHooks.shared.image(.iconPeerMusicChevron).precomposed(secondaryText)
        chevron.sizeToFit()
        
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        
        control.frame = bounds
        textView.resize(frame.width - 60)
        
        container.setFrameSize(NSMakeSize(container.subviewsWidthSize.width + 6, frame.height))
        
        imageView.centerY(x: 0)
        textView.centerY(x: imageView.frame.maxX + 3)
        if let line = textView.textLayout?.lines.first {
            let glyphCenter = line.frame.minY - (titleFont.ascender + titleFont.descender) / 2
            textView.setFrameOrigin(NSMakePoint(textView.frame.minX, floorToScreenPixels(backingScaleFactor, frame.height / 2 - glyphCenter)))
        }
        chevron.centerY(x: textView.frame.maxX + 3)
        
        container.center()
    }
}
