import Foundation
import QuartzCore
import WidgetSandbox
import Twidget3D
import Twidget3DSandbox
import TwidgetIcons

enum LabSandbox {
    static let features: Set<String> = ["binaryOps", "canvasWords", "webAnimations"]

    static let setup: Void = {
        _ = Twidget3DLibrary.provideThree()
        EnginePool.shared.features = features
    }()

    final class Backend: Widget3DBackend {
        let base = Twidget3DBackend()
        var isAvailable: Bool { base.isAvailable }
        var adapterSource: String? { base.adapterSource }

        func makeSurface() -> Widget3DSurface {
            let surface = base.makeSurface()
            if let made = surface as? Twidget3DSurface {
                LabSandbox.lock.lock()
                LabSandbox.surfaces = LabSandbox.surfaces.filter { $0.value != nil } + [Weak(value: made)]
                LabSandbox.lock.unlock()
            }
            return surface
        }
    }

    struct Weak {
        weak var value: Twidget3DSurface?
    }

    static let lock = NSLock()
    static var surfaces: [Weak] = []

    static var surfaceStats: [HTML3DStats] {
        lock.lock()
        defer { lock.unlock() }
        return surfaces.compactMap { $0.value?.session.stats }
    }
}

func labOptions() -> WidgetHost.Options {
    _ = LabSandbox.setup
    var options = WidgetHost.Options()
    options.maximumHeight = option("--max-height").flatMap(Double.init).map { CGFloat($0) } ?? 900
    options.features = LabSandbox.features
    options.asyncValidation = true
    options.sharedValidatorThread = true
    options.startBeforeRendererReady = true
    options.pools = true
    options.policy = .strict
    options.assetResolver = TwidgetIcons.resolver
    options.sideChannels = [{ Widget3DChannel(backend: LabSandbox.Backend()) }]
    return options
}

extension WidgetHost {
    var surfaceStats: [HTML3DStats] {
        LabSandbox.surfaceStats
    }
}
