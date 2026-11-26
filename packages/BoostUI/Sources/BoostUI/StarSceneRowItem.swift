import Foundation
import Cocoa
import TGUIKit
import SceneEffects
import GeneralRows

public final class StarSceneRowItem : GeneralRowItem {
    
    public init(_ initialSize: NSSize, stableId: AnyHashable) {
        super.init(initialSize, height: 100, stableId: stableId)
    }
    public override var accessibilityIsSpacer: Bool {
        return true
    }

    public override func viewClass() -> AnyClass {
        return StarSceneRowView.self
    }
}

private final class StarSceneRowView : TableRowView {
    private let scene: PremiumStarSceneView = PremiumStarSceneView(frame: NSMakeRect(0, 0, 340, 180))
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(scene)
        scene.updateLayout(size: scene.frame.size, transition: .immediate)
        
        self.layer?.masksToBounds = false
    }
    
    override func layout() {
        super.layout()
        scene.center()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
}
