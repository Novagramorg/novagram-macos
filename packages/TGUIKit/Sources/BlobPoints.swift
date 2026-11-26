import Cocoa

public func generateBlobPoints(pointsCount: Int, randomness: CGFloat) -> [CGPoint] {
    let angle = (CGFloat.pi * 2) / CGFloat(pointsCount)
    
    let rgen = { () -> CGFloat in
        let accuracy: UInt32 = 1000
        let random = arc4random_uniform(accuracy)
        return CGFloat(random) / CGFloat(accuracy)
    }
    let rangeStart: CGFloat = 1 / (1 + randomness / 10)
    
    let startAngle = angle * CGFloat(arc4random_uniform(100)) / CGFloat(100)
    
    return (0 ..< pointsCount).map { i -> CGPoint in
        let randPointOffset = (rangeStart + CGFloat(rgen()) * (1 - rangeStart)) / 2
        let angleRandomness: CGFloat = angle * 0.1
        let randAngle = angle + angle * ((angleRandomness * CGFloat(arc4random_uniform(100)) / CGFloat(100)) - angleRandomness * 0.5)
        let pointX = sin(startAngle + CGFloat(i) * randAngle)
        let pointY = cos(startAngle + CGFloat(i) * randAngle)
        return CGPoint(x: pointX * randPointOffset, y: pointY * randPointOffset)
    }
}
