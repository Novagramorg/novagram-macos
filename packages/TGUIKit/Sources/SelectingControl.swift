import Cocoa

public class SelectingControl: Control {
    
   
    private var selectedLayer: SimpleLayer?
    private let unselectedLayer = SimpleLayer()
    private var unselectedImage:CGImage
    private var selectedImage:CGImage
    
    public override func isAccessibilityElement() -> Bool {
        return TGUIKitAccessibility.isEnabled && !isAccessibilityDecorative && !isHidden
    }

    public override func accessibilityRole() -> NSAccessibility.Role? {
        return .checkBox
    }

    public override func accessibilityValue() -> Any? {
        return NSNumber(value: isSelected ? 1 : 0)
    }

    public init(unselectedImage:CGImage, selectedImage:CGImage, selected: Bool = false) {
        self.unselectedImage = unselectedImage
        self.selectedImage = selectedImage
        
        super.init(frame:NSMakeRect(0, 0, max(unselectedImage.backingSize.width ,selectedImage.backingSize.width ), max(unselectedImage.backingSize.height,selectedImage.backingSize.height )))
        userInteractionEnabled = false
        unselectedLayer.contents = unselectedImage
        unselectedLayer.frame = focus(unselectedImage.backingSize)
        layer?.addSublayer(unselectedLayer)
        self.set(selected: selected, animated: false)
        
        self.layer?.masksToBounds = false
    }
    
    public func update(unselectedImage: CGImage, selectedImage: CGImage, selected: Bool, animated: Bool) {
        if self.unselectedImage !== unselectedImage {
            self.unselectedImage = unselectedImage
            unselectedLayer.contents = unselectedImage
        }
        if self.selectedImage !== selectedImage {
            self.selectedImage = selectedImage
            selectedLayer?.contents = selectedImage
        }
        self.set(selected: selected, animated: animated)
        updateImageFrames()
    }

    public override func layout() {
        super.layout()
        updateImageFrames()
    }

    private func updateImageFrames() {
        unselectedLayer.frame = focus(unselectedImage.backingSize)
        selectedLayer?.frame = focus(selectedImage.backingSize)
    }

    public func set(selected: Bool, animated: Bool = false) {
        if selected != isSelected {
            self.isSelected = selected
            if selected {
                let selectedLayer = SimpleLayer()
                selectedLayer.contents = selectedImage
                selectedLayer.frame = focus(selectedImage.backingSize)
                self.selectedLayer = selectedLayer
                layer?.addSublayer(selectedLayer)
                if animated {
                    selectedLayer.animateAlpha(from: 0, to: 1, duration: 0.2)
                    selectedLayer.animateScaleSpring(from: 0.2, to: 1.0, duration: 0.3)
                }
            } else if let selectedLayer = self.selectedLayer {
                self.selectedLayer = nil
                if animated {
                    selectedLayer.animateScaleSpring(from: 1, to: 0.2, duration: 0.3, removeOnCompletion: false)
                    selectedLayer.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak selectedLayer] _ in
                        selectedLayer?.removeFromSuperlayer()
                    })
                } else {
                    selectedLayer.removeFromSuperlayer()
                }
            }
        }
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required public init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        
    }
    
}
