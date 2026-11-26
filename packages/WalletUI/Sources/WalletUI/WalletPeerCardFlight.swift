import Cocoa

struct WalletPeerCardFlight {
    let transform: CATransform3D
    let center: CGPoint
    let alpha: CGFloat
    let maskEdge: CGFloat?
    let shutterScale: CGFloat
    let shutterAlpha: CGFloat
    let slotAlpha: CGFloat
    let buttonProgress: CGFloat

    static func smooth(_ value: CGFloat) -> CGFloat {
        let value = max(0, min(1, value))
        return value * value * (3 - 2 * value)
    }

    static func frame(progress: CGFloat, dismissing: Bool, source: CGRect, card: CGRect) -> WalletPeerCardFlight {
        let p = max(0, min(1, progress))
        if p == 1 {
            return WalletPeerCardFlight(transform: CATransform3DIdentity, center: CGPoint(x: card.midX, y: card.midY), alpha: 1, maskEdge: nil, shutterScale: 0.5, shutterAlpha: 0, slotAlpha: 1, buttonProgress: 1)
        }
        let impact: CGFloat = dismissing ? 1 : 0.5
        let tail = 1 - smooth((p - 0.88) / 0.12)
        func flight(_ time: CGFloat, start: CGFloat, arrival: CGFloat, hold: CGFloat = 0) -> CGFloat {
            let arrival = dismissing ? 0 : arrival
            let hold = hold * impact
            if time < impact {
                let t = max(0, time - hold) / (impact - hold)
                return (t * t * t - 2 * t * t + t) * start + (-2 * t * t * t + 3 * t * t) + (t * t * t - t * t) * arrival
            }
            let elapsed = time - impact
            return 1 + arrival / ((impact - hold) * 14) * exp(-6 * elapsed) * sin(14 * elapsed) * tail
        }
        let halfWidth = card.width * 0.5
        let halfHeight = card.height * 0.5
        let corners = [CGPoint(x: -halfWidth, y: -halfHeight), CGPoint(x: halfWidth, y: -halfHeight), CGPoint(x: halfWidth, y: halfHeight), CGPoint(x: -halfWidth, y: halfHeight)]
        let camera = max(280, card.width * 1.2)
        func pose(pitch: CGFloat, yaw: CGFloat, roll: CGFloat, scale: CGFloat) -> CATransform3D {
            var transform = CATransform3DIdentity
            transform.m34 = -tail / camera
            transform = CATransform3DRotate(transform, pitch, 1, 0, 0)
            transform = CATransform3DRotate(transform, yaw, 0, 1, 0)
            transform = CATransform3DRotate(transform, roll, 0, 0, 1)
            return CATransform3DScale(transform, scale, scale, 1)
        }
        func project(_ transform: CATransform3D) -> [CGPoint] {
            return corners.map { point in
                let w = max(0.001, point.x * transform.m14 + point.y * transform.m24 + transform.m44)
                return CGPoint(x: (point.x * transform.m11 + point.y * transform.m21) / w, y: (point.x * transform.m12 + point.y * transform.m22) / w)
            }
        }
        let slotPitch: CGFloat = 50 * .pi / 180
        let slotScale = min(1, source.width / max(1, card.height))
        let slotReach = project(pose(pitch: slotPitch, yaw: 0, roll: -.pi / 2, scale: slotScale)).map { abs($0.x) }.max() ?? halfHeight
        let startScale = slotScale * min(1, source.width * 0.45 / max(1, slotReach))
        let slotLine = source.midY
        let sidewaysHold: CGFloat = card.minY < slotLine && !dismissing ? 0.6 : 0.45
        func cardPose(_ time: CGFloat) -> (transform: CATransform3D, travel: CGFloat, sideTravel: CGFloat, velocity: CGFloat) {
            let travel = flight(time, start: 1.2, arrival: 0.16, hold: 0.1)
            let twist = smooth((time / impact - sidewaysHold + 0.05) / 0.3)
            let velocity = (flight(time + 0.004, start: 1.2, arrival: 0.16, hold: 0.1) - flight(time - 0.004, start: 1.2, arrival: 0.16, hold: 0.1)) / 0.008 * impact / 1.5 * twist
            return (pose(
                pitch: slotPitch * (1 - flight(time, start: 0, arrival: 0.16, hold: 0.38)),
                yaw: velocity * 9 * .pi / 180,
                roll: -(1 - flight(time, start: 0, arrival: 0.18, hold: 0.4)) * .pi / 2,
                scale: startScale + (1 - startScale) * flight(time, start: 0, arrival: 0.13, hold: 0.4)),
                travel, flight(time, start: 0, arrival: 0.16, hold: sidewaysHold), velocity)
        }
        func baseCenterY(_ projected: [CGPoint], travel: CGFloat) -> CGFloat {
            let start = slotLine - (projected.map { $0.y }.max() ?? halfHeight)
            return start + (card.midY - start) * travel
        }
        let peak: CGFloat = dismissing ? 0.42 : 0.6 * impact
        let peakPose = cardPose(peak)
        let peakProjected = project(peakPose.transform)
        let clearance = max(0, slotLine + 4 - (baseCenterY(peakProjected, travel: peakPose.travel) + (peakProjected.map { $0.y }.min() ?? -halfHeight)))
        let current = cardPose(p)
        let peakTravel = max(0.001, peakPose.travel)
        let dip: CGFloat
        if p < peak {
            dip = current.travel / peakTravel
        } else {
            let fallSpan = dismissing ? 1 - peak : 0.8 * impact
            let peakSlope = (cardPose(peak + 0.004).travel - cardPose(peak - 0.004).travel) / 0.008 / peakTravel
            let t = min(1, (p - peak) / fallSpan)
            dip = (2 * t * t * t - 3 * t * t + 1) + (t * t * t - 2 * t * t + t) * peakSlope * fallSpan
        }
        let center = CGPoint(x: source.midX + (card.midX - source.midX) * current.sideTravel + card.width * 0.055 * current.velocity,
                             y: baseCenterY(project(current.transform), travel: current.travel) + clearance * dip)
        let clipped = p < (clearance > 0 ? peak : (dismissing ? 0.75 : impact))
        let shutterLift = smooth(p / (dismissing ? 0.42 : 0.16))
        return WalletPeerCardFlight(transform: current.transform, center: center, alpha: smooth(p / 0.045),
            maskEdge: clipped ? halfHeight + slotLine - center.y : nil,
            shutterScale: 1 - shutterLift * 0.5,
            shutterAlpha: 1 - smooth((p - (dismissing ? 0.08 : 0.03)) / (dismissing ? 0.45 : 0.17)),
            slotAlpha: shutterLift,
            buttonProgress: flight(p - (dismissing ? 0 : 0.06), start: 2.4, arrival: 0.25))
    }
}
