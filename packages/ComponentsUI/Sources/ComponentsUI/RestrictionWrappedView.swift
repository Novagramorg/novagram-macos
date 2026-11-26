import Cocoa
import TGUIKit

open class RestrictionWrappedView : Control {
    private let textView: TextView = TextView()
    private var text:String
    required public init(frame frameRect: NSRect) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public init(_ text:String) {
        self.text = text
        super.init()
        addSubview(textView)
        textView.userInteractionEnabled = false
        updateLocalizationAndTheme(theme: presentation)
    }
    
    public func update(_ text: String) {
        self.text = text
        updateLocalizationAndTheme(theme: presentation)
    }
    
    open override func updateLocalizationAndTheme(theme: PresentationTheme) {
        self.backgroundColor = theme.colors.background
        let layout = TextViewLayout(.initialize(string: text, color: theme.colors.grayText, font: .normal(.text)), alignment: .center)
        layout.measure(width: frame.width - 40)
        textView.update(layout)
        textView.backgroundColor = theme.colors.background
        needsLayout = true
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func layout() {
        super.layout()
        textView.resize(frame.width - 40)
        textView.center()
    }
}
