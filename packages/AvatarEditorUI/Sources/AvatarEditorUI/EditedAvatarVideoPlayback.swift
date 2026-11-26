import Foundation

func initialAvatarVideoScrubberValues(duration: Double) -> VideoScrubberValues? {
    guard duration.isFinite, duration > 0 else { return nil }
    let maximum = min(1, 10 / duration)
    guard EditedAvatarVideoRange(duration: duration, leftTrim: 0, rightTrim: maximum, keyFrame: nil) != nil else { return nil }
    return VideoScrubberValues(movePos: 0, keyFrame: nil, leftTrim: 0, rightTrim: CGFloat(maximum), minDist: CGFloat(min(1, 1 / duration)), maxDist: CGFloat(maximum), paused: true, suspended: false)
}
