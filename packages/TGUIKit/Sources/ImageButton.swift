import Cocoa
import ColorPalette

public enum ButtonHoverPolicy {
    case none
    case enlarge(value: CGFloat)
}

public enum ButtonBackgroundCornerRadius {
    case none
    case appSpecific
    case half
}

public enum ImageButtonAnimationPolicy {
    case animateContents
    case replaceScale
}

open class ImageButton: Button {

    public private(set) var imageView:ImageView = {
        let view = ImageView()
        view.isAccessibilityDecorative = true
        return view
    }()
    internal private(set) var additionBackgroundView: View?

    private var additionStateBackground:[ControlState:NSColor] = [:]
    private var cornerRadius:[ControlState : ButtonBackgroundCornerRadius] = [:]

    private var hoverAdditionPolicy:[ControlState : ButtonHoverPolicy] = [:]

    private var additionBackgroundMultiplier:[ControlState: CGFloat] = [:]

    private var images:[ControlState:CGImage] = [:]

    public var opticalCentering: Bool = false {
        didSet {
            if opticalCentering != oldValue {
                needsLayout = true
            }
        }
    }

    private var opticalOffsetImage: CGImage?
    private var opticalOffset: NSPoint = .zero

    private var _glassView: LiquidGlassView?
    private var _glassSize: NSSize?
    internal var _glassContentTint: NSColor?

    public var onGlassAppearanceChange: ((NSAppearance) -> Void)? {
        didSet {
            _glassView?.onAppearanceChange = onGlassAppearanceChange
        }
    }

    public var glassForceAppearance: LiquidGlassAppearance {
        get { return _glassView?.forceAppearance ?? .automatic }
        set {
            _glassView?.forceAppearance = newValue
            _glassView?.updateLocalizationAndTheme(theme: presentation)
        }
    }

    /// The tint the caller asked for. Stored separately from `_glassView.customTint`
    /// so we can drop the visible tint while `isEnabled == false` and bring
    /// it back when the button becomes interactive again, without the caller
    /// having to track the original color themselves.
    private var _intendedGlassTint: NSColor?

    public var glassTintColor: NSColor? {
        get { return _intendedGlassTint }
        set {
            _intendedGlassTint = newValue
            _applyEffectiveGlassTint(animated: false, duration: 0.25)
        }
    }

    private func _applyEffectiveGlassTint(animated: Bool, duration: TimeInterval) {
        let effective: NSColor? = _intendedGlassTint
        if animated {
            _glassView?.setCustomTint(effective, animated: true, duration: duration)
        } else {
            _glassView?.customTint = effective
        }
        let override: NSColor?
        if let effective {
            override = effective.lightness > 0.8 ? NSColor.black : NSColor.white
        } else {
            override = nil
        }
        if _glassContentTint != override {
            _glassContentTint = override
            apply(state: self.controlState)
        }
    }

    open override var isEnabled: Bool {
        didSet {
            if isEnabled != oldValue, _intendedGlassTint != nil {
                _applyEffectiveGlassTint(animated: false, duration: 0.25)
            }
        }
    }

    open override func hitTest(_ point: NSPoint) -> NSView? {
        guard let target = super.hitTest(point) else {
            return nil
        }
        if let glass = _glassView, target === glass || target.isDescendant(of: glass) {
            return self
        }
        return target
    }

    public func setGlassEffect(size: NSSize? = nil, tintColor: NSColor? = nil, forceAppearance: LiquidGlassAppearance? = nil, interactive: Bool = true) {
        guard _glassView == nil else { return }
        let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: 999, hasShadow: true, hasBorder: true, forceAppearance: forceAppearance, customTint: tintColor)
        _intendedGlassTint = tintColor
        glass.customTint = tintColor
        glass.onAppearanceChange = { [weak self] appearance in
            self?.onGlassAppearanceChange?(appearance)
        }
        self.layer?.masksToBounds = false
        self.autohighlight = false
        self.shadow = nil
        self.addSubview(glass, positioned: .below, relativeTo: imageView)
        _glassView = glass
        _glassSize = size
        if interactive {
            self.interactiveGlassView = glass
        }
        needsLayout = true
    }

    public func setGlassEffectHidden(_ hidden: Bool) {
        _glassView?.isHidden = hidden
    }

    public var glassSize: NSSize? {
        get { return _glassSize }
        set { _glassSize = newValue; needsLayout = true }
    }

    public func removeImage(for state:ControlState) {
        images.removeValue(forKey: state)
        apply(state: self.controlState)
        
    }
    
    public func setImageContentGravity(_ gravity: CALayerContentsGravity) {
        imageView.contentGravity = gravity
    }
    
    public func set(image:CGImage, for state:ControlState) -> Void {
        if images[state] != image {
            images[state] = image
            apply(state: self.controlState)
        }
    }
    
    open override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
    }
    
    override func prepare() {
        super.prepare()
        imageView.animates = true
        self.addSubview(imageView)
    }

    private func makeAdditionBackgroundIfNeeded() -> View {
        if let view = additionBackgroundView {
            return view
        }
        let view = View()
        view.isEventLess = true
        additionBackgroundView = view
        return view
    }

    private func attachAdditionBackgroundIfNeeded(_ color: NSColor) {
        guard additionBackgroundView?.superview == nil, (color.usingColorSpace(.sRGB)?.alphaComponent ?? 1) > 0 else {
            return
        }
        let additionBackgroundView = makeAdditionBackgroundIfNeeded()
        if let first = subviews.first(where: { !($0 is VisualEffect) }) {
            addSubview(additionBackgroundView, positioned: .below, relativeTo: first)
        } else {
            addSubview(additionBackgroundView)
        }
    }
    
    public func set(additionBackgroundColor:NSColor, for state:ControlState) -> Void {
        additionStateBackground[state] = additionBackgroundColor
        apply(state: self.controlState)
    }
    public func set(additionBackgroundMultiplier: CGFloat, for state:ControlState) -> Void {
        self.additionBackgroundMultiplier[state] = additionBackgroundMultiplier
        apply(state: self.controlState)
    }
    
    
    public func set(cornerRadius: ButtonBackgroundCornerRadius, for state:ControlState) -> Void {
        self.cornerRadius[state] = cornerRadius
        apply(state: self.controlState)
    }
    public func set(hoverAdditionPolicy: ButtonHoverPolicy, for state:ControlState) -> Void {
        self.hoverAdditionPolicy[state] = hoverAdditionPolicy
        apply(state: self.controlState)
    }
    
    
    

    public override var animates: Bool {
        didSet {
            imageView.animates = animates
        }
    }
    
    private var previousState: ControlState?
    
    private var styleHighlightCache: (source: CGImage, backgroundColor: NSColor, highlightColor: NSColor, scale: CGFloat, result: CGImage)?
    private var tintHighlightCache: (source: CGImage, tint: NSColor, scale: CGFloat, result: CGImage)?

    private func cachedStyleHighlight(_ image: CGImage) -> CGImage {
        let backgroundColor = style.backgroundColor
        let highlightColor = style.highlightColor
        guard backgroundColor.type == .componentBased, highlightColor.type == .componentBased else {
            return style.highlight(image: image)
        }
        let scale = System.backingScale
        if let cache = styleHighlightCache, cache.source === image, cache.scale == scale, cache.backgroundColor.isEqual(backgroundColor), cache.highlightColor.isEqual(highlightColor) {
            return cache.result
        }
        let result = style.highlight(image: image)
        styleHighlightCache = (source: image, backgroundColor: backgroundColor, highlightColor: highlightColor, scale: scale, result: result)
        return result
    }

    private func cachedTintHighlight(_ image: CGImage, tint: NSColor) -> CGImage {
        guard tint.type == .componentBased else {
            return image.highlight(color: tint)
        }
        let scale = System.backingScale
        if let cache = tintHighlightCache, cache.source === image, cache.scale == scale, cache.tint.isEqual(tint) {
            return cache.result
        }
        let result = image.highlight(color: tint)
        tintHighlightCache = (source: image, tint: tint, scale: scale, result: result)
        return result
    }

    override public func apply(state: ControlState) {
        let previous = self.previousState
        let state:ControlState = self.isSelected ? .Highlight : state
        super.apply(state: state)
        self.previousState = state

        if _glassView != nil {
            self.layer?.backgroundColor = NSColor.clear.cgColor
            additionBackgroundView?.backgroundColor = .clear
        }
        
        
        var updated: CGImage?

        if let image = images[state], isEnabled {
            updated = image
        } else if state == .Highlight && autohighlight, isEnabled, let image = images[.Normal] {
            updated = cachedStyleHighlight(image)
        } else if state == .Hover && highlightHovered, isEnabled, let image = images[.Normal] {
            updated = cachedStyleHighlight(image)
        } else {
            updated = images[.Normal]
        }

        if let tint = _glassContentTint, let image = updated {
            updated = cachedTintHighlight(image, tint: tint)
        }

        if imageView.image != updated {
            self.imageView.image = updated
        }
       // if state != previousState {
            if self.imageView.alphaValue != 1 {
                self.imageView.animator().alphaValue = 1
            }
            
            if let policy = self.hoverAdditionPolicy[state], previous != state {
                switch policy {
                case .none:
                    break
                case let .enlarge(value):
                    let additionBackgroundView = makeAdditionBackgroundIfNeeded()
                    let current = additionBackgroundView.layer?.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat ?? 1.0
                    additionBackgroundView.layer?.animateScaleSpring(from: current, to: value, duration: 0.35, removeOnCompletion: false)
                }
            }
            
            if let color = self.additionStateBackground[state] ?? self.additionStateBackground[.Normal] {
                attachAdditionBackgroundIfNeeded(color)
                additionBackgroundView?.backgroundColor = color
            } else {
                additionBackgroundView?.backgroundColor = .clear
            }

            if additionBackgroundView == nil, let radius = self.cornerRadius[state], radius != .none {
                _ = makeAdditionBackgroundIfNeeded()
            }
            updateLayout()
            
            if let cornerRadius = self.cornerRadius[state] {
                switch cornerRadius {
                case .none:
                    self.layer?.cornerRadius = 0
                    self.additionBackgroundView?.layer?.cornerRadius = 0
                case .appSpecific:
                    self.layer?.cornerRadius = .cornerRadius
                    self.additionBackgroundView?.layer?.cornerRadius = .cornerRadius
                case .half:
                    self.layer?.cornerRadius = max(frame.width, frame.height) / 2
                    if let additionBackgroundView = additionBackgroundView {
                        additionBackgroundView.layer?.cornerRadius = max(additionBackgroundView.frame.width, additionBackgroundView.frame.height) / 2
                    }
                }
            }
        //}
    }
    
    public func applyAnimation(from: CGImage, to: CGImage, animation: ImageButtonAnimationPolicy) {
        switch animation {
        case .animateContents:
            self.imageView.image = to
        case .replaceScale:
            let imageView = self.imageView
            imageView.image = from
            let newImageView = ImageView()
            self.imageView = newImageView
            newImageView.image = to
            newImageView.sizeToFit()
            addSubview(newImageView)
            newImageView.center()
            
            
            imageView.layer?.animateScaleCenter(from: 1, to: 0.1, duration: 0.25, removeOnCompletion: false, completion: { [weak imageView] _ in
                imageView?.removeFromSuperview()
            })
            imageView.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false)
            
            newImageView.layer?.animateScaleCenter(from: 0.1, to: 1, duration: 0.25, removeOnCompletion: true)
        }
    }
    
    public func disableActions() {
        animates = false
        self.layer?.disableActions()
        layer?.removeAllAnimations()
        imageView.animates = false
      //  imageView.layer?.disableActions()
    }
    
    open override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
    }
    
    @discardableResult override public func sizeToFit(_ addition: NSSize = NSZeroSize, _ maxSize:NSSize = NSZeroSize, thatFit:Bool = false, transition: ContainedViewLayoutTransition = .immediate) -> Bool {
        _ = super.sizeToFit(addition, maxSize, thatFit: thatFit, transition: transition)

        if let image = images[.Normal] {
            var size = image.backingSize

            if maxSize.width > 0 || maxSize.height > 0 {
                size = maxSize
            }

            size.width += addition.width
            size.height += addition.height
            transition.updateFrame(view: self, frame: NSRect(origin: frame.origin, size: size))
            updateLayout(size: size, transition: transition)
        }
        return true
    }
    
    open override func layout() {
        super.layout()
        updateLayout()
    }
    
    public override func updateLayout() {
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }

    open override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        if let image = self.imageView.image {
            switch imageView.contentGravity {
            case .resize, .resizeAspectFill:
                transition.updateFrame(view: imageView, frame: NSRect(origin: .zero, size: size))
            default:
                let imgSize = image.backingSize
                var origin = NSMakePoint((size.width - imgSize.width) / 2, (size.height - imgSize.height) / 2)
                if opticalCentering {
                    let offset = currentOpticalOffset(image)
                    origin.x += offset.x
                    origin.y += offset.y
                }
                transition.updateFrame(view: imageView, frame: NSRect(origin: origin, size: imgSize))
            }
        }

        if let additionBackgroundView = additionBackgroundView {
            let abSize: NSSize
            if let multiplier = additionBackgroundMultiplier[controlState] {
                abSize = NSMakeSize(floorToScreenPixels(backingScaleFactor, size.width * multiplier), floorToScreenPixels(backingScaleFactor, size.height * multiplier))
            } else {
                abSize = size
            }
            transition.updateFrame(view: additionBackgroundView, frame: NSRect(origin: NSMakePoint((size.width - abSize.width) / 2, (size.height - abSize.height) / 2), size: abSize))
        }

        if let glassView = _glassView {
            let gs = _glassSize ?? size
            let gx = (size.width - gs.width) / 2
            let gy = (size.height - gs.height) / 2
            transition.updateFrame(view: glassView, frame: NSMakeRect(gx, gy, gs.width, gs.height))
            glassView.updateLayout(size: gs, transition: transition)
        }
    }
    
    private func currentOpticalOffset(_ image: CGImage) -> NSPoint {
        if opticalOffsetImage !== image {
            opticalOffsetImage = image
            opticalOffset = imageOpticalCenterOffset(image)
        }
        return opticalOffset
    }

    open override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        _glassView?.updateLocalizationAndTheme(theme: theme)
    }

}
