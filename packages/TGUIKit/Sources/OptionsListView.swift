import Cocoa

public final class OptionsListView: View {
    
    public final class Option {
        public let image: CGImage
        public let header: TextViewLayout
        public let text: TextViewLayout
        public let infoImage: CGImage?
        public let textInset: CGFloat
        public let widthInset: CGFloat
        public let interactiveText: Bool
        public private(set) var width: CGFloat
        
        public init(image: CGImage, header: TextViewLayout, text: TextViewLayout, width: CGFloat, infoImage: CGImage? = nil, textInset: CGFloat = 40, widthInset: CGFloat = 0, interactiveText: Bool = false) {
            self.image = image
            self.header = header
            self.text = text
            self.infoImage = infoImage
            self.textInset = textInset
            self.widthInset = widthInset
            self.interactiveText = interactiveText
            self.width = width
            self.makeSize(width: width)
        }
        
        public func makeSize(width: CGFloat) {
            self.width = width
            self.header.measure(width: width - textInset)
            self.text.measure(width: width - textInset)
        }
        
        public var size: NSSize {
            return NSMakeSize(width - widthInset, header.layoutSize.height + 5 + text.layoutSize.height)
        }
    }
    
    private final class OptionView: View {
        private let imageView = ImageView()
        private let titleView = TextView()
        private let infoView = TextView()
        private var infoImageView: ImageView?
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(imageView)
            addSubview(titleView)
            addSubview(infoView)
            
            titleView.userInteractionEnabled = false
            titleView.isSelectable = false
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(option: Option) {
            self.infoView.userInteractionEnabled = option.interactiveText
            self.infoView.isSelectable = option.interactiveText
            self.titleView.update(option.header)
            self.infoView.update(option.text)
            self.imageView.image = option.image
            self.imageView.sizeToFit()
            
            if let infoImage = option.infoImage {
                let view: ImageView
                if let current = self.infoImageView {
                    view = current
                } else {
                    view = ImageView()
                    self.infoImageView = view
                    addSubview(view)
                }
                view.image = infoImage
                view.sizeToFit()
            } else if let view = self.infoImageView {
                view.removeFromSuperview()
                self.infoImageView = nil
            }
        }
        
        override func layout() {
            super.layout()
            titleView.setFrameOrigin(NSMakePoint(40, 0))
            infoView.setFrameOrigin(NSMakePoint(40, titleView.frame.maxY + 5))
            infoImageView?.setFrameOrigin(NSMakePoint(40, titleView.frame.maxY + 5))
        }
    }
    
    public var spacing: CGFloat = 20
    
    public static func contentSize(options: [Option], spacing: CGFloat) -> NSSize {
        var size = NSMakeSize(0, 0)
        for (i, option) in options.enumerated() {
            size = NSMakeSize(max(option.width, size.width), option.size.height + size.height)
            if i != options.count - 1 {
                size.height += spacing
            }
        }
        return size
    }
    
    public static func height(options: [Option], spacing: CGFloat) -> CGFloat {
        return contentSize(options: options, spacing: spacing).height
    }
    
    public func update(options: [Option]) {
        while subviews.count > options.count {
            subviews.last?.removeFromSuperview()
        }
        while subviews.count < options.count {
            addSubview(OptionView(frame: .zero))
        }
        for (i, option) in options.enumerated() {
            let view = subviews[i] as! OptionView
            view.update(option: option)
            view.setFrameSize(option.size)
        }
        setFrameSize(OptionsListView.contentSize(options: options, spacing: spacing))
        needsLayout = true
    }
    
    override public func layout() {
        super.layout()
        var y: CGFloat = 0
        for subview in subviews {
            subview.centerX(y: y)
            y += subview.frame.height
            y += spacing
        }
    }
}
