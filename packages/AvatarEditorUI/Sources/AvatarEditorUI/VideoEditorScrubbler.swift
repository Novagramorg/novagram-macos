import Cocoa
import TGUIKit
import Localization

private final class ScrubberMoveView: Control {
    private let view = View()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        view.isEventLess = true
        addSubview(view)
        view.layer?.cornerRadius = 2
        view.backgroundColor = .white
    }
    
    
    override func layout() {
        super.layout()
        view.frame = bounds
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ScrubberleftTrim: Control {
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    override func draw(_ layer: CALayer, in ctx: CGContext) {
        ctx.round(bounds, flags: [.left, .top, .bottom])
        ctx.setFillColor(NSColor.accent.cgColor)
        ctx.fill(bounds)
    }
    
    override func layout() {
        super.layout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ScrubberrightTrim: Control {
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
    }
    
    override func draw(_ layer: CALayer, in ctx: CGContext) {
        ctx.round(bounds, flags: [.right, .top, .bottom])
        ctx.setFillColor(NSColor.accent.cgColor)
        ctx.fill(bounds)
    }
    
    override func layout() {
        super.layout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public struct VideoScrubberValues : Equatable {
    public let movePos: CGFloat
    public let leftTrim: CGFloat
    public let rightTrim: CGFloat
    public let minDist: CGFloat
    public let maxDist: CGFloat
    public let paused: Bool
    public let keyFrame: CGFloat?
    public let suspended: Bool
    public init(movePos: CGFloat, keyFrame: CGFloat?, leftTrim: CGFloat, rightTrim: CGFloat, minDist: CGFloat, maxDist: CGFloat, paused: Bool, suspended: Bool) {
        self.movePos = movePos
        self.keyFrame = keyFrame
        self.leftTrim = leftTrim
        self.rightTrim = rightTrim
        self.minDist = minDist
        self.paused = paused
        self.maxDist = maxDist
        self.suspended = suspended
    }
    
    public func withUpdatedMove(_ movePos: CGFloat) -> VideoScrubberValues {
        return VideoScrubberValues(movePos: min(max(0, movePos), 1), keyFrame: keyFrame, leftTrim: leftTrim, rightTrim: rightTrim, minDist: minDist, maxDist: maxDist, paused: paused, suspended: suspended)
    }
    public func withUpdatedleftTrim(_ leftTrim: CGFloat) -> VideoScrubberValues {
        var keyFrame = self.keyFrame
        if let frame = keyFrame, leftTrim > frame {
            keyFrame = nil
        }
        return VideoScrubberValues(movePos: movePos, keyFrame: keyFrame, leftTrim: min(max(0, leftTrim), 1), rightTrim: rightTrim, minDist: minDist, maxDist: maxDist, paused: paused, suspended: suspended)
    }
    public func withUpdatedrightTrim(_ rightTrim: CGFloat) -> VideoScrubberValues {
        var keyFrame = self.keyFrame
        if let frame = keyFrame, rightTrim < frame {
            keyFrame = nil
        }
        return VideoScrubberValues(movePos: movePos, keyFrame: keyFrame, leftTrim: leftTrim, rightTrim: min(max(0, rightTrim), 1), minDist: minDist, maxDist: maxDist, paused: paused, suspended: suspended)
    }
    public func withMovedTrim(by delta: CGFloat) -> VideoScrubberValues {
        let width = self.rightTrim - self.leftTrim
        guard delta.isFinite, self.leftTrim.isFinite, self.rightTrim.isFinite, width > 0, width <= 1 else { return self }
        let left = min(max(0, self.leftTrim + delta), 1 - width)
        let right = left + width
        let keyFrame = self.keyFrame.flatMap { $0 >= left && $0 <= right ? $0 : nil }
        return VideoScrubberValues(movePos: self.movePos, keyFrame: keyFrame, leftTrim: left, rightTrim: right, minDist: self.minDist, maxDist: self.maxDist, paused: self.paused, suspended: self.suspended)
    }

    public func withUpdatedMinDist(_ minDist: CGFloat) -> VideoScrubberValues {
        return VideoScrubberValues(movePos: movePos, keyFrame: keyFrame, leftTrim: leftTrim, rightTrim: rightTrim, minDist: minDist, maxDist: maxDist, paused: paused, suspended: suspended)
    }
    public func withUpdatedMaxDist(_ maxDist: CGFloat) -> VideoScrubberValues {
        return VideoScrubberValues(movePos: movePos, keyFrame: keyFrame, leftTrim: leftTrim, rightTrim: rightTrim, minDist: minDist, maxDist: maxDist, paused: paused, suspended: suspended)
    }
    public func withUpdatedPaused(_ paused: Bool) -> VideoScrubberValues {
        return VideoScrubberValues(movePos: movePos, keyFrame: keyFrame, leftTrim: leftTrim, rightTrim: rightTrim, minDist: minDist, maxDist: maxDist, paused: paused, suspended: suspended)
    }
    
    public func withUpdatedKeyFrame(_ keyFrame: CGFloat?) -> VideoScrubberValues {
        return VideoScrubberValues(movePos: movePos, keyFrame: keyFrame, leftTrim: leftTrim, rightTrim: rightTrim, minDist: minDist, maxDist: maxDist, paused: paused, suspended: suspended)
    }
    public func withUpdatedSuspended(_ suspended: Bool) -> VideoScrubberValues {
        return VideoScrubberValues(movePos: movePos, keyFrame: keyFrame, leftTrim: leftTrim, rightTrim: rightTrim, minDist: minDist, maxDist: maxDist, paused: paused, suspended: suspended)
    }
}

open class VideoEditorScrubblerControl : View, ViewDisplayDelegate {
    private let scrubber: ScrubberMoveView
    private var imageViewsContainer: View = View()
    private let overlay: View = View()
    private let distance = Control()
    private let leftTrim: ScrubberleftTrim = ScrubberleftTrim(frame: .zero)
    private let rightTrim: ScrubberrightTrim = ScrubberrightTrim(frame: .zero)
    
    private var values = VideoScrubberValues(movePos: 0, keyFrame: nil, leftTrim: 0, rightTrim: 1.0, minDist: 0, maxDist: 1, paused: false, suspended: false)
    
    public var updateValues:((VideoScrubberValues)->Void)? = nil
    
    public required init(frame frameRect: NSRect) {
        scrubber = ScrubberMoveView(frame: NSMakeRect(0, 0, 4, frameRect.height))
        super.init(frame: frameRect)
        addSubview(self.imageViewsContainer)
        imageViewsContainer.layer?.cornerRadius = .cornerRadius
        imageViewsContainer.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        addSubview(self.scrubber)

        overlay.isEventLess = true
        overlay.displayDelegate = self
        overlay.layer?.cornerRadius = .cornerRadius
        addSubview(overlay)
        
        addSubview(leftTrim)
        addSubview(rightTrim)
        
        addSubview(distance)

        let shadow = NSShadow()
        shadow.shadowBlurRadius = 5
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.2)
        shadow.shadowOffset = NSMakeSize(0, 2)
        self.scrubber.shadow = shadow
        
        
        let shadow1 = NSShadow()
        shadow1.shadowBlurRadius = 5
        shadow1.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow1.shadowOffset = NSMakeSize(0, 2)
        self.shadow = shadow1
        
        
        func possibleDrag(_ value: CGFloat) -> Bool {
            return value >= 0 && value <= 1
        }
        func checkDist(_ leftValue: CGFloat, _ rightValue: CGFloat, _ min: CGFloat, _ max: CGFloat) -> Bool {
            return (leftValue - rightValue) >= min && (leftValue - rightValue) <= max
        }
        
        var leftTrimStart: NSPoint? = nil
        var rightTrimStart: NSPoint? = nil
        var distanceStart: NSPoint? = nil


        leftTrim.set(handler: { control in
            leftTrimStart = control.window?.mouseLocationOutsideOfEventStream ?? nil
        }, for: .Down)
        
        leftTrim.set(handler: { [weak self] _ in
            guard let `self` = self else {
                return
            }
            leftTrimStart = nil
            self.updateValues?(self.values.withUpdatedPaused(false).withUpdatedSuspended(false))
        }, for: .Up)
        
        
        leftTrim.set(handler: { [weak self] control in
            guard let `self` = self, let start = leftTrimStart, let current = control.window?.mouseLocationOutsideOfEventStream else {
                return
            }
            
            let difference = start - current
            
            let width = self.imageViewsContainer.frame.size.width
            guard width.isFinite, width > 0 else { return }
            
            let newValue = control.frame.origin - difference
            
            let percent = newValue.x / width
            
            if checkDist(self.values.rightTrim, percent, self.values.minDist, self.values.maxDist) {
                if possibleDrag(percent) {
                    leftTrimStart = current
                    control.setFrameOrigin(newValue)
                }
                if percent != self.values.leftTrim {
                    self.updateValues?(self.values.withUpdatedleftTrim(percent).withUpdatedPaused(true).withUpdatedSuspended(false))
                }
            }
        }, for: .MouseDragging)
        
        
        rightTrim.set(handler: { control in
            rightTrimStart = control.window?.mouseLocationOutsideOfEventStream ?? nil
        }, for: .Down)
        
        rightTrim.set(handler: { [weak self] _ in
            guard let `self` = self else {
                return
            }
            rightTrimStart = nil
            self.updateValues?(self.values.withUpdatedPaused(false).withUpdatedSuspended(false))
        }, for: .Up)
        
        
        rightTrim.set(handler: { [weak self] control in
            guard let `self` = self, let start = rightTrimStart, let current = control.window?.mouseLocationOutsideOfEventStream else {
                return
            }
            let difference = start - current
            let width = self.imageViewsContainer.frame.size.width
            guard width.isFinite, width > 0 else { return }

            let newValue = control.frame.origin - difference
            var percent = (newValue.x - self.leftTrim.frame.width) / width
            
            if percent < 0 && self.values.rightTrim > 0 {
                percent = 0
            }
            if percent > 1 && self.values.rightTrim < 1 {
                percent = 1
            }
            
            if checkDist(percent, self.values.leftTrim, self.values.minDist, self.values.maxDist) {
                if possibleDrag((newValue.x - self.leftTrim.frame.width) / width) {
                    rightTrimStart = current
                    control.setFrameOrigin(newValue)
                }
                self.updateValues?(self.values.withUpdatedrightTrim(percent).withUpdatedPaused(true).withUpdatedSuspended(false))
            }
        }, for: .MouseDragging)
        
        
        distance.setAccessibilityLabel(strings().voiceOverMediaTrimmedRange)
        
        distance.set(handler: { control in
            distanceStart = control.window?.mouseLocationOutsideOfEventStream ?? nil
        }, for: .Down)
        
        
        var chooseFrame: Bool = false
        
        distance.set(handler: { [weak self] control in
            guard let `self` = self else {
                return
            }
            if !self.values.paused {
                guard let keyFrame = self.framePosition(control) else { return }
                self.updateValues?(self.values.withUpdatedSuspended(true).withUpdatedPaused(true).withUpdatedMove(keyFrame))
                chooseFrame = true
            }
            
        }, for: .LongMouseDown)
        
        
        distance.set(handler: { [weak self] control in
            guard let `self` = self else {
                return
            }
            defer {
                chooseFrame = false
                distanceStart = nil
            }
            guard let keyFrame = self.framePosition(control) else { return }
            var values = self.values
            if !self.values.suspended {
                if !values.paused  {
                    if keyFrame != values.keyFrame {
                        values = values.withUpdatedKeyFrame(keyFrame).withUpdatedMove(keyFrame).withUpdatedPaused(true).withUpdatedSuspended(true)
                    }
                } else {
                    values = values.withUpdatedPaused(false)
                }
            } else if self.values.suspended && chooseFrame {
                if keyFrame != values.keyFrame {
                    values = values
                        .withUpdatedKeyFrame(keyFrame)
                        .withUpdatedMove(keyFrame)
                        .withUpdatedPaused(true)
                        .withUpdatedSuspended(true)
                } else {
                    values = values
                        .withUpdatedMove(keyFrame)
                        .withUpdatedPaused(false)
                        .withUpdatedSuspended(false)
                }
            } else {
                values = values.withUpdatedPaused(false).withUpdatedSuspended(false)
            }
            self.updateValues?(values)
        }, for: .Up)
        
        
        distance.set(handler: { [weak self] control in
            guard let `self` = self, let start = distanceStart, let current = control.window?.mouseLocationOutsideOfEventStream else {
                return
            }
            
            let difference = start - current
            let width = self.imageViewsContainer.frame.size.width
            guard width.isFinite, width > 0 else { return }
            let value = difference.x / width
            
            if chooseFrame {
                guard value.isFinite else { return }
                let updatedValue = min(self.values.rightTrim, max(self.values.leftTrim, self.values.movePos - value))
                self.updateValues?(self.values.withUpdatedMove(updatedValue))
                distanceStart = current
            } else {
                let newValues = self.values.withMovedTrim(by: -value)
                if newValues.leftTrim != self.values.leftTrim || newValues.rightTrim != self.values.rightTrim {
                    distanceStart = current
                    self.updateValues?(newValues.withUpdatedPaused(true).withUpdatedSuspended(false))
                }
            }
            
           
            
            

        }, for: .MouseDragging)
        
    }
    
    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        if layer == overlay.layer {
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.85).cgColor)
            if values.leftTrim > 0 {
                ctx.fill(NSMakeRect(0, 0, leftTrim.frame.maxX - imageViewsContainer.frame.minX, imageViewsContainer.frame.height))
            }
            if values.rightTrim < 1 {
                ctx.fill(NSMakeRect(rightTrim.frame.minX - imageViewsContainer.frame.minX, 0, imageViewsContainer.frame.maxX - self.rightTrim.frame.minX, imageViewsContainer.frame.height))
            }
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func render(_ images: [CGImage], size: NSSize) {
        
        while imageViewsContainer.subviews.count > images.count {
            imageViewsContainer.subviews.removeLast()
        }
        while imageViewsContainer.subviews.count < images.count {
            let view = ImageView()
            view.isAccessibilityDecorative = true
            view.contentGravity = .resizeAspectFill
            view.animates = true
            imageViewsContainer.addSubview(view)
        }
        
        var x: CGFloat = 0

        
        for (i, image) in images.enumerated() {
            (imageViewsContainer.subviews[i] as? ImageView)?.image = image
            (imageViewsContainer.subviews[i] as? ImageView)?.frame = NSMakeRect(x, 0, size.width, size.height)
            x += size.width
        }
        needsLayout = true
    }
    
    public func apply(values: VideoScrubberValues) {
        let previousPaused = self.values.paused
        let previousSuspdended = self.values.suspended
        self.values = values
        if previousPaused != values.paused || values.suspended != previousSuspdended {
            self.scrubber.change(opacity: values.paused && !values.suspended ? 0 : 1, animated: !values.paused)
        }
        needsLayout = true
        overlay.needsDisplay = true
    }
    
    func timelinePosition(for value: CGFloat) -> CGFloat {
        let width = frame.size.width.isFinite ? max(0, frame.size.width) : 0
        let inset = min(8, width / 2)
        return inset + min(1, max(0, value.isFinite ? value : 0)) * max(0, width - inset * 2)
    }

    private func framePosition(_ control: Control) -> CGFloat? {
        let width = self.imageViewsContainer.frame.size.width
        guard width.isFinite, width > 0, let location = control.window?.mouseLocationOutsideOfEventStream else { return nil }
        let point = self.imageViewsContainer.convert(location, from: nil)
        guard point.x.isFinite else { return nil }
        return min(self.values.rightTrim, max(self.values.leftTrim, point.x / width))
    }

    public override func layout() {
        super.layout()
        let width = frame.size.width.isFinite ? max(0, frame.size.width) : 0
        let height = frame.size.height.isFinite ? max(0, frame.size.height) : 0
        let handleWidth = min(8, width / 2)
        let contentHeight = max(0, height - 4)
        let contentY = (height - contentHeight) / 2
        self.imageViewsContainer.frame = NSMakeRect(handleWidth, contentY, max(0, width - handleWidth * 2), contentHeight)

        let left = timelinePosition(for: values.leftTrim)
        let right = max(left, timelinePosition(for: values.rightTrim))
        leftTrim.frame = NSMakeRect(left - handleWidth, contentY, handleWidth, contentHeight)
        rightTrim.frame = NSMakeRect(right, contentY, handleWidth, contentHeight)
        let position = min(right, max(left, timelinePosition(for: values.movePos)))
        let scrubberWidth = min(4, width)
        self.scrubber.frame = NSMakeRect(min(max(0, position - scrubberWidth / 2), width - scrubberWidth), 0, scrubberWidth, height)
        self.distance.frame = NSMakeRect(left, contentY, right - left, contentHeight)

        let count = imageViewsContainer.subviews.count
        if count > 0 {
            let imageWidth = imageViewsContainer.frame.width / CGFloat(count)
            for (index, view) in imageViewsContainer.subviews.enumerated() {
                view.frame = NSMakeRect(CGFloat(index) * imageWidth, 0, imageWidth, contentHeight)
            }
        }
        overlay.frame = imageViewsContainer.frame
    }
}
