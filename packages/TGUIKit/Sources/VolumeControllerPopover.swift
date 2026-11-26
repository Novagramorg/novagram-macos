import Cocoa

public class VolumeControllerPopover: GenericViewController<HorizontalSliderControl> {

    
    private let initialValue: CGFloat
    private let updatedValue: (CGFloat)->Void
    public init(initialValue: CGFloat, updatedValue: @escaping(CGFloat)->Void) {
        self.initialValue = initialValue
        self.updatedValue = updatedValue
        super.init(frame: NSMakeRect(0, 0, 30, 100))
        bar = .init(height: 0)
    }
    
    public override var isAutoclosePopover: Bool {
        return false
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        genericView.value = initialValue
        genericView.updateInteractiveValue = updatedValue
        
        readyOnce()
    }
    
    public override func becomeFirstResponder() -> Bool? {
        return nil
    }
    
    public var value:CGFloat = 0 {
        didSet {
            genericView.value = value
        }
    }
    
}
