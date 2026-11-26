import Cocoa
import TGUIKit
import TelegramCore
import TelegramTheme
import TelegramUtils
import Postbox



final class LegacyChatMessageAccessoryView: Control {

    private let textView:TextView = TextView()
    private let backgroundView = View()
    private var maxWidth: CGFloat = 0
    private let unread = View()
    private var stringValue: String = ""
    private var textLayoutKey: (string: String, color: NSColor, maximumNumberOfLines: Int32, maxWidth: CGFloat)?
    private var textLayout: TextViewLayout?
    
    private let progress: RadialProgressView = RadialProgressView(theme: RadialProgressTheme(backgroundColor: .clear, foregroundColor: .white, cancelFetchingIcon: stopFetchStreamableControl), twist: true, size: NSMakeSize(24, 24))
    private let bufferingIndicator: ProgressIndicator = ProgressIndicator(frame: NSMakeRect(0, 0, 10, 10))
    private let download: ImageButton = ImageButton(frame: NSMakeRect(0, 0, 24, 24))

    private var status: MediaResourceStatus?
    private var isStreamable: Bool = true
    private var isCompact: Bool = false
    
    private var imageView: ImageView?
    
    private var visualEffect: VisualEffect?
    
    public var soundOffOnImage: CGImage? {
        didSet {
            if let soundOffOnImage = soundOffOnImage {
                if imageView == nil {
                    imageView = ImageView()
                    imageView?.animates = true
                    addSubview(imageView!)
                }
                imageView?.image = soundOffOnImage
                imageView?.sizeToFit()
            } else {
                imageView?.removeFromSuperview()
                imageView = nil
            }
        }
    }
    
    private let progressCap: View = View()
    public var isUnread: Bool = false
    public override func layout() {
        super.layout()
        visualEffect?.frame = bounds
        download.centerY(x: 6)
        progress.centerY(x: 6)
        backgroundView.frame = bounds
        
        bufferingIndicator.centerY(x: frame.width - bufferingIndicator.frame.width - 7)
        if let imageView = imageView {
            imageView.centerY(x: frame.width - imageView.frame.width - 6)
        }
        
        if let textLayout = textView.textLayout {
            var rect = focus(textLayout.layoutSize)
            rect.origin.x = 6
            if hasStremingControls  {
                rect.origin.x += download.frame.width + 6
            }
            if backingScaleFactor == 2 {
                rect.origin.y += 0.5
            } else {
                rect.origin.y += 1
            }
            textView.frame = rect
            
            unread.centerY(x: rect.maxX + 2)

        }
        
    }
    
    public var hasStremingControls: Bool {
        return !download.isHidden || !progress.isHidden
    }
    
    private var fetch:(()->Void)?
    private var cancelFetch:(()->Void)?
    private var click:(()->Void)?
    
    private var isVideoMessage: Bool = false
    
    public func updateText(_ text: String, maxWidth: CGFloat, status: MediaResourceStatus?, isStreamable: Bool, isCompact: Bool = false, soundOffOnImage: CGImage? = nil, isBuffering: Bool = false, isUnread: Bool = false, animated: Bool = false, isVideoMessage: Bool = false, fetch: @escaping()-> Void = { }, cancelFetch: @escaping()-> Void = { }, click: @escaping()-> Void = { }) -> Void {
        
        
        let animated = animated && self.isCompact != isCompact
        
        let string = isStreamable && !isCompact ? text.components(separatedBy: ", ").joined(separator: "\n") : text
        let color = isVideoMessage ? theme.chatServiceItemTextColor : .white
        let maximumNumberOfLines: Int32 = isStreamable && !isCompact ? 2 : 1
        let updatedText: TextViewLayout
        if let key = self.textLayoutKey, let current = self.textLayout, key.string == string, key.color == color, key.maximumNumberOfLines == maximumNumberOfLines, key.maxWidth == maxWidth {
            updatedText = current
        } else {
            updatedText = TextViewLayout(.initialize(string: string, color: color, font: .normal(10.0)), maximumNumberOfLines: maximumNumberOfLines, truncationType: .end, alwaysStaticItems: true)
            updatedText.measure(width: maxWidth)
            self.textLayoutKey = (string, color, maximumNumberOfLines, maxWidth)
            self.textLayout = updatedText
        }
        textView.update(updatedText)
        
        backgroundView.backgroundColor = isVideoMessage ? theme.chatServiceItemColor : .blackTransparent

        
        self.isStreamable = isStreamable
        self.status = status
        self.stringValue = text
        self.maxWidth = maxWidth
        self.fetch = fetch
        self.isCompact = isCompact
        self.cancelFetch = cancelFetch
        self.click = click
        self.soundOffOnImage = soundOffOnImage
        self.isUnread = isUnread

        self.bufferingIndicator.isHidden = !isBuffering
        self.unread.isHidden = !isUnread

        if let status = status, isStreamable {
            
            download.set(image: isCompact ? theme.icons.videoCompactFetching : theme.icons.streamingVideoDownload, for: .Normal)

            
            switch status {
            case .Remote:
                progress.isHidden = true
                download.isHidden = false
            case .Local:
                progress.isHidden = true
                download.isHidden = true
            case let .Fetching(_, progress), let .Paused(progress):
                self.progress.state = !isCompact ? .Fetching(progress: progress, force: false) : .None
                self.progress.isHidden = isCompact
                download.isHidden = !isCompact
                download.set(image: isCompact ? theme.icons.compactStreamingFetchingCancel : theme.icons.streamingVideoDownload, for: .Normal)
            }
            if isCompact {
                download.setFrameSize(10, 10)
            } else {
                download.setFrameSize(28, 28)

            }
        } else {
            progress.isHidden = true
            download.isHidden = true
            progress.state = .None
        }
        
        let newSize = NSMakeSize(min(max(soundOffOnImage != nil ? 30 : updatedText.layoutSize.width, updatedText.layoutSize.width) + 12 + (isUnread ? 8 : 0) + (hasStremingControls ? download.frame.width + 6 : 0) + (soundOffOnImage != nil ? soundOffOnImage!.backingSize.width + 2 : 0) + (isBuffering ? bufferingIndicator.frame.width + 4 : 0), maxWidth), hasStremingControls && !isCompact ? 36 : updatedText.layoutSize.height + 6)
        change(size: newSize, animated: animated)
        backgroundView.change(size: newSize, animated: animated)
        
        
        backgroundView.layer?.cornerRadius = isStreamable ? 8 : newSize.height / 2

        
        var rect = focus(updatedText.layoutSize)
        rect.origin.x = 6
        if hasStremingControls  {
            rect.origin.x += download.frame.width + 6
        }
        if backingScaleFactor == 2 {
            rect.origin.y += 0.5
        }
        textView.change(pos: rect.origin, animated: animated)
        
        if animated, let layer = backgroundView.layer {
            let cornerAnimation = CABasicAnimation(keyPath: "cornerRadius")
            cornerAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            cornerAnimation.fromValue = layer.presentation()?.cornerRadius ?? layer.cornerRadius
            cornerAnimation.toValue =  isStreamable ? 8 : newSize.height / 2
            cornerAnimation.duration = 0.2
            layer.add(cornerAnimation, forKey: "cornerRadius")
        }
        
        if theme.shouldBlurService, !TelegramUtilsHooks.shared.isLite(.blur) {
            let current: VisualEffect
            if let view = self.visualEffect {
                current = view
            } else {
                current = VisualEffect(frame: bounds)
                self.visualEffect = current
                addSubview(current, positioned: .below, relativeTo: self.subviews.first)
            }
            current.layer?.cornerRadius = isStreamable ? 8 : newSize.height / 2
            current.bgColor = theme.blurServiceColor
            backgroundView.backgroundColor = .clear
        } else if let view = visualEffect {
            performSubviewRemoval(view, animated: false)
            self.visualEffect = nil
        }
        
        needsLayout = true
    }
    
    public override func copy() -> Any {
        let view = LegacyChatMessageAccessoryView(frame: frame)
        view.updateText(self.stringValue, maxWidth: self.maxWidth, status: self.status, isStreamable: self.isStreamable, isCompact: self.isCompact)
        return view
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        unread.setFrameSize(NSMakeSize(6, 6))
        unread.layer?.cornerRadius = 3
        unread.backgroundColor = isVideoMessage ? theme.chatServiceItemTextColor : .white
        textView.isSelectable = false
        textView.userInteractionEnabled = false
        textView.disableBackgroundDrawing = true
        
        addSubview(backgroundView)
        addSubview(textView)
        addSubview(progress)
        addSubview(download)
        addSubview(unread)
        bufferingIndicator.background = .clear
        bufferingIndicator.progressColor = isVideoMessage ? theme.chatServiceItemTextColor : .white
        bufferingIndicator.layer?.cornerRadius = bufferingIndicator.frame.height / 2
        bufferingIndicator.isHidden = true
        progress.isHidden = true
        download.isHidden = true
        download.autohighlight = false
        progress.fetchControls = FetchControls(fetch: { [weak self] in
            self?.cancelFetch?()
        })
        
        progressCap.layer?.borderColor = NSColor.white.withAlphaComponent(0.3).cgColor
        progressCap.layer?.borderWidth = 2.0
        progressCap.frame = NSMakeRect(2, 2, progress.frame.width - 4, progress.frame.height - 4)
        progressCap.layer?.cornerRadius = progressCap.frame.width / 2

        progress.addSubview(progressCap)
        
        addSubview(bufferingIndicator)

        
        download.set(handler: { [weak self] _ in
            guard let `self` = self, let status = self.status else {return}
            switch status {
            case .Remote:
                 self.fetch?()
            case .Fetching:
                self.cancelFetch?()
            default:
                break
            }
        }, for: .Click)
        
        set(handler: { [weak self] _ in
            guard let `self` = self, let status = self.status else {return}
            switch status {
            case .Remote:
                self.fetch?()
            case .Fetching:
                self.cancelFetch?()
            default:
                self.click?()
            }
        }, for: .Click)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
