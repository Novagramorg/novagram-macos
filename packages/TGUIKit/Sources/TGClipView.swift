import Cocoa
import CoreVideo
import SwiftSignalKit

public class TGClipView: NSClipView,CALayerDelegate {
    
    var border:BorderType? {
        didSet {
//            self.layerContentsRedrawPolicy = .onSetNeedsDisplay
//            super.needsDisplay = true
//            self.layerContentsRedrawPolicy = .never
        }
    }
    
    var shouldAnimateOriginChange:Bool = false
    var destinationOrigin:NSPoint?
    
    var backgroundMode: TableBackgroundMode = .plain {
        didSet {
            needsDisplay = true
        }
    }
    
    #if DEBUG
    static let forcesSkipsDisplayOnScroll = UserDefaults.standard.bool(forKey: "PerfLabClipNoDisplay")
    #endif
    public var skipsDisplayOnScroll: Bool = false
    private var isScrollingToPoint = false

    public override var needsDisplay: Bool {
        set {
            if newValue, self.isScrollingToPoint {
                #if DEBUG
                if self.skipsDisplayOnScroll || TGClipView.forcesSkipsDisplayOnScroll {
                    return
                }
                #else
                if self.skipsDisplayOnScroll {
                    return
                }
                #endif
            }
            super.needsDisplay = newValue
        }
        get {
            return super.needsDisplay
        }
    }

    // The clip view never draws (draw(_:) below is empty), but overriding
    // draw(_:) makes AppKit allocate a viewport-sized backing store on every
    // needsDisplay. Taking the updateLayer path keeps the layer content-free.
    public override var wantsUpdateLayer: Bool {
        return true
    }

    public override func updateLayer() {
        super.updateLayer()
    }
    public var _mouseDownCanMoveWindow: Bool = false
    public override var mouseDownCanMoveWindow: Bool {
        return _mouseDownCanMoveWindow
    }
    
    var scrollCompletion:((_ success:Bool) ->Void)?
    private var scrollAnimationId = 0
    
    var scrollDidComplete:((_ success:Bool) ->Void)?

    public var destination: NSPoint? {
        return self.destinationOrigin
    }

    override init(frame frameRect: NSRect) {
        
        super.init(frame: frameRect)
//        self.backgroundColor = .clear
        self.wantsLayer = true
        self.layerContentsRedrawPolicy = .never
      //  self.layer?.drawsAsynchronously = System.drawAsync
        //self.layer?.delegate = self
//        createDisplayLink()

    }
    
    
    
    public override var backgroundColor: NSColor {
        set {
            super.backgroundColor = .clear
        }
        get {
            return .clear
        }
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
//
    public override func draw(_ dirtyRect: NSRect) {
       
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public var isAnimateScrolling:Bool {
        return self.destinationOrigin != nil
    }
    
    override public func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
    }
    func scrollRectToVisible(_ rect: NSRect, animated: Bool) -> Bool {
        self.shouldAnimateOriginChange = animated
        return super.scrollToVisible(rect)
    }
    
    func scrollRectToVisible(_ rect: CGRect, animated: Bool, completion: @escaping (Bool) -> Void) -> Bool {
        self.scrollCompletion = completion
        let success = self.scrollRectToVisible(rect, animated: animated)
        if !animated || !success {
            self.handleCompletionIfNeeded(withSuccess: success)
        }
        return success
    }
    
    var documentOffset: NSPoint {
        return self.point ?? self.bounds.origin
    }
    
    public func updateBounds(to point: NSPoint, cancel: Bool = false) {
        if self.bounds.origin != point || cancel {
            self.scrollAnimationId &+= 1
            let completion = self.scrollCompletion
            self.scrollCompletion = nil
            if self.animatingContentRect != nil {
                self.animatingContentRect = nil
                self.documentView?.needsLayout = true
            }
            if cancel {
                CATransaction.begin()
                NSAnimationContext.beginGrouping()
                NSAnimationContext.current.duration = 0
                self.animator().scroll(to: point)
                self.animator().setBoundsOrigin(point)
                NSAnimationContext.endGrouping()
                CATransaction.commit()
            } else {
                self.scroll(to: point)
            }
            
            self.destinationOrigin = nil
            self.point = nil
            completion?(false)
            self.scrollDidComplete?(true)
        }
    }
        
    private(set) var point: NSPoint?
    private(set) var animatingContentRect: NSRect?
    
    
    public func scroll(to point: NSPoint, animated:Bool, timingFunction: CAMediaTimingFunctionName = .spring, duration: Double = 0.35, completion: @escaping (Bool) -> Void = {_ in})  {

        if animated, point == self.destinationOrigin {
            self.scrollCompletion = completion
            return
        }
        self.scrollAnimationId &+= 1
        let animationId = self.scrollAnimationId
        self.scrollCompletion = completion
        self.destinationOrigin = point

        let minimumY: CGFloat = self.documentView?.isFlipped == true ? -(self.enclosingScrollView?.contentInsets.top ?? 0) : 0

        if animated, point.y >= minimumY {

            self.point = point

            let currentBounds = (self.layer?.presentation()?.bounds ?? self.bounds)

            if abs(currentBounds.minY - point.y) <= frame.height {
                let toBounds = CGRect(origin: point, size: self.bounds.size)
                let animatingContentRect = currentBounds.union(toBounds)
                self.animatingContentRect = animatingContentRect
                self._changeBounds(from: currentBounds, to: toBounds, animated: animated, duration: duration, timingFunction: timingFunction, completion: { [weak self] completed in
                    guard let self, self.scrollAnimationId == animationId else {
                        return
                    }
                    if self.animatingContentRect == animatingContentRect {
                        self.animatingContentRect = nil
                        self.documentView?.needsLayout = true
                    }
                    self.destinationOrigin = nil
                    self.point = nil
                    if completed {
                        self.setBoundsOrigin(point)
                    }
                    let completion = self.scrollCompletion
                    self.scrollCompletion = nil
                    completion?(completed && point == self.bounds.origin)
                    self.scrollDidComplete?(completed && point == self.bounds.origin)
                })

            } else {
                self.animatingContentRect = nil
                self.setBoundsOrigin(NSMakePoint(currentBounds.minX, currentBounds.minY < point.y ? point.y - frame.height : point.y + frame.height))
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.35
                    let timingFunction = CAMediaTimingFunction(controlPoints: 0.5, 1.0 + 0.4 / 3.0, 1.0, 1.0)
                    ctx.timingFunction = timingFunction
                    self.animator().setBoundsOrigin(point)
                }, completionHandler: { [weak self] in
                    guard let self, self.scrollAnimationId == animationId else { return }
                    self.destinationOrigin = nil
                    self.point = nil
                    self.setBoundsOrigin(point)
                    let completion = self.scrollCompletion
                    self.scrollCompletion = nil
                    completion?(point == self.bounds.origin)
                    self.scrollDidComplete?(point == self.bounds.origin)
                })
            }

        } else {
            let completion = self.scrollCompletion
            self.scrollCompletion = nil
            self.updateBounds(to: NSMakePoint(point.x, max(point.y, minimumY)))
            self.point = nil
            self.destinationOrigin = nil
            completion?(true)
            self.scrollDidComplete?(true)
        }

    }
    
    func cancelScrolling() {
        if let point = self.destinationOrigin {
            updateBounds(to: point, cancel: true)
        }
    }
    
    public override func scroll(_ point: NSPoint) {
        super.scroll(point)
    }
    
    public override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(newOrigin)
    }
    
    
    public override var bounds: NSRect {
        set {
            super.bounds = newValue
        }
        get {
            return super.bounds
        }
    }
    
    public override func scroll(to newOrigin: NSPoint) {
        self.isScrollingToPoint = true
        super.scroll(to: newOrigin)
        self.isScrollingToPoint = false
    }
    
    func handleCompletionIfNeeded(withSuccess success: Bool) {
        self.destinationOrigin = nil
        if self.scrollCompletion != nil {
          //  super.scroll(to: bounds.origin)
            self.scrollCompletion!(success)
            self.scrollCompletion = nil
        }
    }
    
    
    public override func isAccessibilityElement() -> Bool {
        return false
    }
    public override func accessibilityParent() -> Any? {
        return TGUIKitAccessibility.parent(of: self, default: { super.accessibilityParent() })
    }
}
