import Cocoa

public protocol GlassEffectContainer: AnyObject {
    var spacing: CGFloat { get set }
    var contentView: NSView? { get set }
}

/// Marker class for the content view of a `GlassEffectContainer`. Identifying
/// it lets `ContainedViewLayoutTransition` skip frame updates: the container
/// auto-sizes its `contentView` to match its own bounds, so any explicit
/// `updateFrame` would either be a no-op or fight that auto-sizing.
/// `flip` is set by the owning `GlassContainerView`; direct constructors get
/// the `FlippableView` default of `true`.
open class GlassContentView: FlippableView {
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.masksToBounds = false
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@available(macOS 26.0, *)
extension NSGlassEffectContainerView: GlassEffectContainer {}

@available(macOS 26.0, *)
public final class FlippedGlassEffectContainerView: NSGlassEffectContainerView {

    private let _flipped: Bool

    public init(frame frameRect: NSRect, flipped: Bool = true) {
        self._flipped = flipped
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.spacing = 5
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var isFlipped: Bool {
        return _flipped
    }
}

/// Fallback container for systems without NSGlassEffectContainerView. Provides
/// the same `contentView`/`spacing` surface so the factory can return one
/// unified protocol type. `spacing` is a no-op here — there is nothing to
/// merge — but is accepted to keep the call-site API identical.
public final class LegacyGlassEffectContainerView: FlippableView, GlassEffectContainer {

    public var spacing: CGFloat = 0

    public var contentView: NSView? {
        didSet {
            if oldValue !== contentView {
                oldValue?.removeFromSuperview()
            }
            if let cv = contentView, cv.superview !== self {
                addSubview(cv)
            }
        }
    }

    public init(frame frameRect: NSRect, flipped: Bool) {
        super.init(frame: frameRect)
        self.flip = flipped
        self.backgroundColor = .clear
        self.layer?.masksToBounds = false
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}

/// Builds a glass-effect container appropriate for the current OS. Call sites
/// hold the result as `(NSView & GlassEffectContainer)?` so they can set
/// `contentView`/`spacing` without branching on availability.
public func makeGlassEffectContainer(frame: NSRect, flipped: Bool = true, spacing: CGFloat = 5) -> NSView & GlassEffectContainer {
    let container: NSView & GlassEffectContainer
    if #available(macOS 26.0, *), System.liquidGlass {
        container = FlippedGlassEffectContainerView(frame: frame, flipped: flipped)
    } else {
        container = LegacyGlassEffectContainerView(frame: frame, flipped: flipped)
    }
    container.spacing = spacing
    return container
}
