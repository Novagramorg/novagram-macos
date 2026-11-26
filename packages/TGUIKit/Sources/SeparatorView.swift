import Cocoa

open class SeparatorView : View {
    private let textView = TextView()
    private var text: String = ""
    
    required public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        
        textView.userInteractionEnabled = false
        textView.isSelectable = false
    }
    
    public convenience init(frame frameRect: NSRect, text: String) {
        self.init(frame: frameRect)
        self.update(text: text)
    }
    
    public func update(text: String) {
        self.text = text
        let layout = TextViewLayout(.initialize(string: text, color: presentation.colors.grayText, font: .normal(.text)))
        layout.measure(width: .greatestFiniteMagnitude)
        textView.update(layout)
        needsLayout = true
        needsDisplay = true
    }
    
    open override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.update(text: self.text)
    }
    
    open override func layout() {
        super.layout()
        textView.center()
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        
        ctx.setFillColor(presentation.colors.border.cgColor)
        ctx.fill(NSMakeRect(textView.frame.minX - 10 - 60, frame.height / 2, 60, .borderSize))
        ctx.fill(NSMakeRect(textView.frame.maxX + 10, frame.height / 2, 60, .borderSize))

    }
}
