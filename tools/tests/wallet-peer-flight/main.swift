import Cocoa

func near(_ a: CGFloat, _ b: CGFloat, tolerance: CGFloat = 0.001) {
    precondition(abs(a - b) < tolerance, "\(a) differs from \(b)")
}
let card = CGRect(x: 320, y: 260, width: 360, height: 228)
let sources = [CGRect(x: 100, y: 120, width: 100, height: 30), CGRect(x: 600, y: 380, width: 160, height: 36), CGRect(x: 10, y: 600, width: 65, height: 26)]
var checked = 0
for source in sources {
    for dismissing in [false, true] {
        let start = WalletPeerCardFlight.frame(progress: 0, dismissing: dismissing, source: source, card: card)
        near(start.alpha, 0)
        near(start.center.x, source.midX)
        near(start.shutterAlpha, 1)
        near(start.slotAlpha, 0)
        precondition(start.maskEdge != nil)
        precondition(abs(start.transform.m12) > 0.01, "Card must start sideways")
        let end = WalletPeerCardFlight.frame(progress: 1, dismissing: dismissing, source: source, card: card)
        near(end.center.x, card.midX, tolerance: 0.01)
        near(end.center.y, card.midY, tolerance: 0.01)
        near(end.transform.m11, 1)
        near(end.transform.m22, 1)
        near(end.transform.m34, 0)
        near(end.alpha, 1)
        near(end.shutterAlpha, 0)
        near(end.buttonProgress, 1)
        precondition(end.maskEdge == nil)
        var previous: WalletPeerCardFlight?
        for index in 0...1000 {
            let progress = CGFloat(index) / 1000
            let pose = WalletPeerCardFlight.frame(progress: progress, dismissing: dismissing, source: source, card: card)
            let matrix = pose.transform
            let values = [pose.center.x, pose.center.y, matrix.m11, matrix.m12, matrix.m13, matrix.m14, matrix.m21, matrix.m22, matrix.m23, matrix.m24, matrix.m31, matrix.m32, matrix.m33, matrix.m34, matrix.m41, matrix.m42, matrix.m43, matrix.m44, pose.buttonProgress]
            precondition(values.allSatisfy { $0.isFinite })
            precondition((0...1).contains(pose.alpha) && (0...1).contains(pose.shutterAlpha))
            if let previous {
                precondition(hypot(pose.center.x - previous.center.x, pose.center.y - previous.center.y) < 15, "Card trajectory must be continuous")
            }
            previous = pose
            checked += 1
        }
    }
}
print("Passed \(checked) wallet flight samples: opening/closing endpoints, slot clipping, rotation, finite transforms, and continuity")
