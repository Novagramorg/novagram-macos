import Foundation
import Cocoa
import TGUIKit
import TelegramTheme

final class WidgetButton: Button {
    private let textView = TextView()
    private let image = SimpleLayer()
    private var text: String = ""
    override init() {
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    private func setup() {
        addSubview(textView)
        image.masksToBounds = true
        image.zPosition = 1
        layer?.addSublayer(image)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        scaleOnClick = true
        self.layer?.masksToBounds = false
    }
    

    func update(_ isSelected: Bool, icon: CGImage, text: String) {
        self.text = text

        let color = isSelected ? theme.colors.accent : theme.colors.text

        let textLayout = TextViewLayout(.initialize(string: text, color: color, font: .medium(.short)))
        textLayout.measure(width: .greatestFiniteMagnitude)
        textView.update(textLayout)

        self.isSelected = isSelected
        layer?.borderColor = isSelected ? theme.colors.accent.cgColor : theme.colors.border.cgColor
        layer?.borderWidth = (isSelected ? 1.66 : (theme.bubbled ? 0 : 1))
        
        image.contents = icon
        image.frame.size = icon.backingSize

    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.background = theme.colors.grayBackground
    }
    
    override func layout() {
        super.layout()

        let x = round((frame.width - (image.frame.width + 4 + textView.frame.width)) / 2.0)
        image.frame.origin = NSMakePoint(x, round((frame.height - image.frame.height) / 2.0))
        layer?.cornerRadius = frame.height / 2
        textView.centerY(x: image.frame.maxX + 4)
    }
    
    func size() -> CGSize {
        return NSMakeSize(textView.frame.width + 20 + image.frame.width + 4, 30)
    }
}
