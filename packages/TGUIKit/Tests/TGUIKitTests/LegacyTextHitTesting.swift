import Cocoa
import TGUIKit

private func legacyClosestRect(rectangles: [CGRect], point: CGPoint) -> CGRect? {
    var closestRect: CGRect?
    var closestYDistance = CGFloat.greatestFiniteMagnitude
    let point = point.offsetBy(dx: 0, dy: 5.0)
    for rect in rectangles {

        let point = NSMakePoint(point.x, point.y + rect.height / 2)
        if rect.contains(point) {
            return rect
        }

        let rectCenterY = rect.midY
        let yDistance = abs(point.y - rectCenterY)

        if yDistance < closestYDistance {
            closestYDistance = yDistance
            closestRect = rect
        }
    }

    return closestRect
}

extension TextViewLayout {
    func legacyFindIndex(location:NSPoint) -> Int {

        if location.y == .greatestFiniteMagnitude {
            return lines.count - 1
        } else if location.y == 0 {
            return 0
        }

        let rect = legacyClosestRect(rectangles: self.lines.map { $0.frame }, point: location)
        return lines.firstIndex(where: { $0.frame == rect }) ?? 0
    }
}
