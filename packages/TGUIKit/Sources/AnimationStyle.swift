import Cocoa

public struct AnimationStyle {

    public let duration:CFTimeInterval
    public let function:CAMediaTimingFunctionName
    public init(duration: CFTimeInterval, function: CAMediaTimingFunctionName) {
        self.duration = duration
        self.function = function
    }
}
