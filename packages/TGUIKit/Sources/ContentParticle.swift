import Cocoa

public struct ContentParticle {
    public var position: CGPoint
    public var direction: CGPoint
    public var velocity: CGFloat
    public var alpha: CGFloat
    public var lifetime: Double
    public var beginTime: Double
    
    public init(position: CGPoint, direction: CGPoint, velocity: CGFloat, alpha: CGFloat, lifetime: Double, beginTime: Double) {
        self.position = position
        self.direction = direction
        self.velocity = velocity
        self.alpha = alpha
        self.lifetime = lifetime
        self.beginTime = beginTime
    }
}
