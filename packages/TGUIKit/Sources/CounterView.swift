import Cocoa

open class CounterView : View {
    private let textView = TextView()
    private let imageView = ImageView()
    required public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        addSubview(imageView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func update(_ text: TextViewLayout, image: CGImage) {
        self.textView.update(text)
        self.imageView.image = image
        self.imageView.sizeToFit()
        self.setFrameSize(NSMakeSize(text.layoutSize.width + imageView.frame.width + 4, text.layoutSize.height))
    }
    
    open override func layout() {
        super.layout()
        self.imageView.centerY(x: 0)
        textView.centerY(x: self.imageView.frame.maxX + 4)
    }
}
