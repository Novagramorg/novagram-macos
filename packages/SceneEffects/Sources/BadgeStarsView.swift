import Cocoa
import Foundation
import TGUIKit
import SceneKit

public final class BadgeStarsView: NSView, PremiumDecorationProtocol {
    private let sceneView: SCNView
    
    private var leftParticles: SCNNode?
    private var rightParticles: SCNNode?
    
    public override init(frame: CGRect) {
        self.sceneView = SCNView(frame: CGRect(origin: .zero, size: frame.size))
        self.sceneView.backgroundColor = .clear
        if let url = Bundle.main.url(forResource: "badge", withExtension: "scn") {
            self.sceneView.scene = try? SCNScene(url: url, options: nil)
        }
        
        super.init(frame: frame)
        wantsLayer = true
        self.layer?.opacity = 0.0
        
        self.addSubview(self.sceneView)
        
        self.leftParticles = self.sceneView.scene?.rootNode.childNode(withName: "leftParticles", recursively: false)
        self.rightParticles = self.sceneView.scene?.rootNode.childNode(withName: "rightParticles", recursively: false)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func setVisible(_ visible: Bool) {
        if visible, let leftParticles = self.leftParticles, let rightParticles = self.rightParticles, leftParticles.parent == nil {
            self.sceneView.scene?.rootNode.addChildNode(leftParticles)
            self.sceneView.scene?.rootNode.addChildNode(rightParticles)
        }
        
        self._change(opacity: visible ? 0.6 : 0.0, animated: true, completion: { [weak self] finished in
            if let strongSelf = self, finished && !visible && strongSelf.leftParticles?.parent != nil {
                strongSelf.leftParticles?.removeFromParentNode()
                strongSelf.rightParticles?.removeFromParentNode()
            }
        })
    }
    
    public func resetAnimation() {
    }
    public func startAnimation() {
    }
    
    public override func layout() {
        super.layout()
        self.sceneView.frame = CGRect(origin: .zero, size: frame.size)
    }
}

