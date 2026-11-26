import AppKit
import TGUIKit

// Standalone harness for the modal morph (links only TGUIKit).
//   Interactive (default): `swift run ModalMorphLab`  -> click the blue attach button to open,
//                          "Close" inside the sheet to close. Morph is slowed for inspection.
//   Capture:  `swift run ModalMorphLab auto <outputDir>` -> auto open/close, writes a contact sheet.

typealias WindowListCreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

private func registerPlaceholderImages() {
    for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor.black.setFill(); rect.insetBy(dx: 4, dy: 4).fill(); return true
        }
        _ = image.setName(name)
    }
}

// A distinct modal class so it does NOT auto-close a same-class modal underneath (real nesting).
private final class DemoModalControllerB: ModalViewController {
    var bgColor = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1)
    override var containerBackground: NSColor { return bgColor }
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.wantsLayer = true
        let title = TextView()
        let layout = TextViewLayout(.initialize(string: "Transaction", color: .white, font: .medium(16)))
        layout.measure(width: 200); title.update(layout)
        title.setFrameOrigin(NSMakePoint(20, 18)); self.view.addSubview(title)
        for i in 0 ..< 3 {
            let row = View(frame: NSMakeRect(16, 54 + CGFloat(i) * 46, self.frame.width - 32, 38))
            row.layer?.cornerRadius = 8; row.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.08)
            self.view.addSubview(row)
        }
        let close = TextButton(frame: NSMakeRect(self.frame.width - 96, self.frame.height - 44, 80, 30))
        close.layer?.cornerRadius = 8; close.set(text: "Close", for: .Normal); close.set(font: .medium(13), for: .Normal)
        close.set(color: .white, for: .Normal); close.set(background: NSColor(calibratedRed: 0.2, green: 0.55, blue: 1, alpha: 1), for: .Normal)
        close.set(handler: { [weak self] _ in self?.close() }, for: .Click)
        self.view.addSubview(close)
        self.readyOnce()
    }
    override var cornerRadius: CGFloat { return 12 }
}

private func memoryFootprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1024.0 / 1024.0 : 0
}

private final class DemoModalController: ModalViewController {
    static var liveCount = 0
    override init(frame frameRect: NSRect) { DemoModalController.liveCount += 1; super.init(frame: frameRect) }
    required init?(coder: NSCoder) { fatalError() }
    deinit { DemoModalController.liveCount -= 1 }
    // Match a real modal (e.g. New Poll): the content view is CLEAR; the opaque fill comes from
    // containerBackground on the outer container. This reproduces the "transparent morph" case.
    var bgColor = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1)
    override var containerBackground: NSColor { return bgColor }
    var interiorRow: NSView?

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.wantsLayer = true

        let title = TextView()
        let layout = TextViewLayout(.initialize(string: "New Poll", color: .white, font: .medium(16)))
        layout.measure(width: 200)
        title.update(layout)
        title.setFrameOrigin(NSMakePoint(20, 18))
        self.view.addSubview(title)

        for i in 0 ..< 4 {
            let row = View(frame: NSMakeRect(16, 54 + CGFloat(i) * 46, self.frame.width - 32, 38))
            row.layer?.cornerRadius = 8
            row.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.08)
            self.view.addSubview(row)
            if i == 1 { self.interiorRow = row }
        }

        let close = TextButton(frame: NSMakeRect(self.frame.width - 96, self.frame.height - 44, 80, 30))
        close.layer?.cornerRadius = 8
        close.set(text: "Close", for: .Normal)
        close.set(font: .medium(13), for: .Normal)
        close.set(color: .white, for: .Normal)
        close.set(background: NSColor(calibratedRed: 0.2, green: 0.55, blue: 1, alpha: 1), for: .Normal)
        close.set(handler: { [weak self] _ in self?.close() }, for: .Click)
        self.view.addSubview(close)

        self.readyOnce()
    }

    override var cornerRadius: CGFloat { return 12 }
}

// A minimal nav-wrapped modal content controller, to verify the morph when the modal is a
// NavigationViewController (settings change-number/birthday, chat suggest-birthday are this shape).
private final class DemoNavContentController: ViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1).cgColor
        let title = TextView()
        let layout = TextViewLayout(.initialize(string: "Nav Content", color: .white, font: .medium(16)))
        layout.measure(width: 200)
        title.update(layout)
        title.setFrameOrigin(NSMakePoint(20, 18))
        self.view.addSubview(title)
        for i in 0 ..< 3 {
            let row = View(frame: NSMakeRect(16, 54 + CGFloat(i) * 46, 288, 38))
            row.layer?.cornerRadius = 8
            row.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.08)
            self.view.addSubview(row)
        }
        self.readyOnce()
    }
}

final class Lab {
    static var shared: Lab?
    func retain() { Lab.shared = self }
    let window: Window
    let control: ImageButton
    let hint: TextView
    let capture: WindowListCreateImage?
    var frames: [(phase: String, image: CGImage)] = []
    let outputDir: URL
    private var openModal: DemoModalController?

    init(outputDir: URL) {
        self.outputDir = outputDir
        let rect = NSMakeRect(0, 0, 460, 560)
        window = Window(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ModalMorphLab"
        let content = View(frame: rect)
        content.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1)
        window.contentView = content

        hint = TextView()
        let hl = TextViewLayout(.initialize(string: "Click the blue button to open the modal.\nClick \u{201C}Close\u{201D} inside it to close. (Run with \u{201C}slow\u{201D} for slow-motion.)", color: NSColor(calibratedWhite: 0.7, alpha: 1), font: .normal(13)))
        hl.measure(width: rect.width - 40)
        hint.update(hl)
        hint.setFrameOrigin(NSMakePoint(20, 90))
        content.addSubview(hint)

        let bar = View(frame: NSMakeRect(0, rect.height - 56, rect.width, 56))
        bar.backgroundColor = NSColor(calibratedWhite: 0.22, alpha: 1)
        bar.autoresizingMask = [.width]
        content.addSubview(bar)

        control = ImageButton(frame: NSMakeRect(12, 8, 40, 40))
        control.layer?.cornerRadius = 20
        control.layer?.masksToBounds = true
        control.set(background: NSColor(calibratedRed: 0.2, green: 0.55, blue: 1, alpha: 1), for: .Normal)
        bar.addSubview(control)

        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            capture = unsafeBitCast(symbol, to: WindowListCreateImage.self)
        } else {
            capture = nil
        }
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    // MARK: Interactive

    func runInteractive(scale: Double) {
        ModalMorphTransition.durationScale = { scale }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        let controlRef = control
        control.set(handler: { [weak self] _ in
            guard let self = self, self.openModal == nil else { return }
            let modal = DemoModalController(frame: NSMakeRect(0, 0, 320, 380))
            self.openModal = modal
            showModal(with: modal, for: self.window, animated: true, morphSource: { [weak controlRef] in controlRef })
        }, for: .Click)
        // track when the modal goes away so the button can reopen it
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let m = self.openModal, m.modal == nil { self.openModal = nil }
        }
        print("ModalMorphLab: interactive. Click the blue button.")
    }

    // MARK: Capture

    private let captureQueue = DispatchQueue(label: "modalmorphlab.capture", qos: .userInteractive)
    private var capturing = false
    private var phase = "pre"
    private let framesLock = NSLock()

    private func snapshotNow() -> CGImage? {
        guard let capture = capture, let image = capture(.null, 8, UInt32(window.windowNumber), 1 | 8)?.takeRetainedValue() else {
            return nil
        }
        return image
    }

    func runCapture(scale: Double) {
        ModalMorphTransition.durationScale = { scale }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        let controlInBar = control
        capturing = true
        captureQueue.async {
            while true {
                self.framesLock.lock(); let on = self.capturing; let ph = self.phase; self.framesLock.unlock()
                if !on { break }
                let t0 = CACurrentMediaTime()
                if let image = self.snapshotNow() {
                    self.framesLock.lock(); let n = self.frames.count; self.frames.append((ph, image)); self.framesLock.unlock()
                    if let dest = CGImageDestinationCreateWithURL(self.outputDir.appendingPathComponent(String(format: "f-%04d-%@.png", n, ph)) as CFURL, "public.png" as CFString, 1, nil) {
                        CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
                    }
                }
                let dt = CACurrentMediaTime() - t0
                if dt < 0.012 { Thread.sleep(forTimeInterval: 0.012 - dt) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.framesLock.lock(); self.phase = "open"; self.framesLock.unlock()
            let modal = DemoModalController(frame: NSMakeRect(0, 0, 320, 380))
            showModal(with: modal, for: self.window, animated: true, morphSource: { [weak controlInBar] in controlInBar })
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1 * scale) {
                self.framesLock.lock(); self.phase = "settle"; self.framesLock.unlock()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.framesLock.lock(); self.phase = "close"; self.framesLock.unlock()
                    modal.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3 * scale) {
                        self.framesLock.lock(); self.capturing = false; self.framesLock.unlock()
                        self.captureQueue.sync {}
                        self.writeContactSheet()
                        print("ModalMorphLab: wrote \(self.frames.count) frames to \(self.outputDir.path)")
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    // Context-menu-from-button: register the OWNER control (as AppMenu.show now does), open the modal with
    // NO morphSource — the owner must be consumed and drive a full open+close morph from/to the button.
    func runCaptureOwner(scale: Double) {
        ModalMorphTransition.durationScale = { scale }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        let controlInBar = control
        capturing = true
        captureQueue.async {
            while true {
                self.framesLock.lock(); let on = self.capturing; let ph = self.phase; self.framesLock.unlock()
                if !on { break }
                if let image = self.snapshotNow() {
                    self.framesLock.lock(); let n = self.frames.count; self.frames.append((ph, image)); self.framesLock.unlock()
                    if let dest = CGImageDestinationCreateWithURL(self.outputDir.appendingPathComponent(String(format: "f-%04d-%@.png", n, ph)) as CFURL, "public.png" as CFString, 1, nil) {
                        CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
                    }
                }
                Thread.sleep(forTimeInterval: 0.012)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.framesLock.lock(); self.phase = "open"; self.framesLock.unlock()
            ModalMorphContextSource.registerOwner(controlInBar)
            let modal = DemoModalController(frame: NSMakeRect(0, 0, 320, 380))
            showModal(with: modal, for: self.window, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1 * scale) {
                self.framesLock.lock(); self.phase = "settle"; self.framesLock.unlock()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.framesLock.lock(); self.phase = "close"; self.framesLock.unlock()
                    modal.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3 * scale) {
                        self.framesLock.lock(); self.capturing = false; self.framesLock.unlock()
                        self.captureQueue.sync {}
                        print("OWNER: wrote \(self.frames.count) frames to \(self.outputDir.path)")
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    // Fallback close morph (wallet card case): open with a real morphSource, then make the source
    // unresolvable before close (remove it from the window, like the settings row recycled behind the
    // wallet modal). morphCandidate() returns nil at close, so the close must fall back to the stored
    // open-time rect and STILL morph toward the control, not plain-fade.
    func runCaptureFallback(scale: Double) {
        ModalMorphTransition.durationScale = { scale }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        let controlInBar = control
        capturing = true
        captureQueue.async {
            while true {
                self.framesLock.lock(); let on = self.capturing; let ph = self.phase; self.framesLock.unlock()
                if !on { break }
                if let image = self.snapshotNow() {
                    self.framesLock.lock(); let n = self.frames.count; self.frames.append((ph, image)); self.framesLock.unlock()
                    if let dest = CGImageDestinationCreateWithURL(self.outputDir.appendingPathComponent(String(format: "f-%04d-%@.png", n, ph)) as CFURL, "public.png" as CFString, 1, nil) {
                        CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
                    }
                }
                Thread.sleep(forTimeInterval: 0.012)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.framesLock.lock(); self.phase = "open"; self.framesLock.unlock()
            let modal = DemoModalController(frame: NSMakeRect(0, 0, 320, 380))
            showModal(with: modal, for: self.window, animated: true, morphSource: { [weak controlInBar] in controlInBar })
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1 * scale) {
                // Source goes unresolvable: removed from the window => morphCandidate's window check fails.
                controlInBar.removeFromSuperview()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.framesLock.lock(); self.phase = "close"; self.framesLock.unlock()
                    modal.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3 * scale) {
                        self.framesLock.lock(); self.capturing = false; self.framesLock.unlock()
                        self.captureQueue.sync {}
                        print("FALLBACK: wrote \(self.frames.count) frames to \(self.outputDir.path)")
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    // Context-menu morph: register the control's snapshot+rect (as AppMenuRowItem.invokeClick does), then open
    // the modal with NO morphSource — the static source drives an OPEN-only morph; the close must be normal.
    func runCaptureMenu(scale: Double) {
        ModalMorphTransition.durationScale = { scale }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        capturing = true
        captureQueue.async {
            while true {
                self.framesLock.lock(); let on = self.capturing; let ph = self.phase; self.framesLock.unlock()
                if !on { break }
                let t0 = CACurrentMediaTime()
                if let image = self.snapshotNow() {
                    self.framesLock.lock(); let n = self.frames.count; self.frames.append((ph, image)); self.framesLock.unlock()
                    if let dest = CGImageDestinationCreateWithURL(self.outputDir.appendingPathComponent(String(format: "f-%04d-%@.png", n, ph)) as CFURL, "public.png" as CFString, 1, nil) {
                        CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
                    }
                }
                let dt = CACurrentMediaTime() - t0
                if dt < 0.012 { Thread.sleep(forTimeInterval: 0.012 - dt) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.framesLock.lock(); self.phase = "open"; self.framesLock.unlock()
            if let img = ModalMorphTransition.controlImage(self.control) {
                let screenRect = self.window.convertToScreen(self.control.convert(self.control.bounds, to: nil))
                ModalMorphContextSource.register(image: img, screenRect: screenRect)
            }
            let modal = DemoModalController(frame: NSMakeRect(0, 0, 320, 380))
            showModal(with: modal, for: self.window, animated: true) // no morphSource -> static context-menu source
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1 * scale) {
                self.framesLock.lock(); self.phase = "settle"; self.framesLock.unlock()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.framesLock.lock(); self.phase = "close"; self.framesLock.unlock()
                    modal.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3 * scale) {
                        self.framesLock.lock(); self.capturing = false; self.framesLock.unlock()
                        self.captureQueue.sync {}
                        self.writeContactSheet()
                        print("ModalMorphLab(menu): wrote \(self.frames.count) frames to \(self.outputDir.path)")
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    // Nav-wrapped modal: the modal is a NavigationViewController (via the morphSource overload).
    func runCaptureNav(scale: Double) {
        ModalMorphTransition.durationScale = { scale }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        let controlInBar = control
        capturing = true
        captureQueue.async {
            while true {
                self.framesLock.lock(); let on = self.capturing; let ph = self.phase; self.framesLock.unlock()
                if !on { break }
                let t0 = CACurrentMediaTime()
                if let image = self.snapshotNow() {
                    self.framesLock.lock(); let n = self.frames.count; self.frames.append((ph, image)); self.framesLock.unlock()
                    if let dest = CGImageDestinationCreateWithURL(self.outputDir.appendingPathComponent(String(format: "f-%04d-%@.png", n, ph)) as CFURL, "public.png" as CFString, 1, nil) {
                        CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
                    }
                }
                let dt = CACurrentMediaTime() - t0
                if dt < 0.012 { Thread.sleep(forTimeInterval: 0.012 - dt) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.framesLock.lock(); self.phase = "open"; self.framesLock.unlock()
            let nav = NavigationViewController(DemoNavContentController(), self.window)
            nav._frameRect = NSMakeRect(0, 0, 320, 380)
            nav.readyOnce()
            showModal(with: nav, for: self.window, animated: true, morphSource: { [weak controlInBar] in controlInBar })
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1 * scale) {
                self.framesLock.lock(); self.phase = "settle"; self.framesLock.unlock()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.framesLock.lock(); self.phase = "close"; self.framesLock.unlock()
                    nav.modal?.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3 * scale) {
                        self.framesLock.lock(); self.capturing = false; self.framesLock.unlock()
                        self.captureQueue.sync {}
                        self.writeContactSheet()
                        print("ModalMorphLab(nav): wrote \(self.frames.count) frames to \(self.outputDir.path)")
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    // Leak test: many open/close cycles mixing normal close, close-DURING-open (cancel path), and the
    // context-menu static source (registry). After draining, no DemoModalController and no extra window
    // subviews should remain.
    func runLeakTest(cycles total: Int = 30) {
        ModalMorphTransition.durationScale = { 1.0 }
        let window = self.window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        let controlRef = control
        let baseline = window.contentView?.subviews.count ?? 0
        var cycle = 0
        func runOne() {
            if cycle >= total {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    autoreleasepool { }
                    let live = DemoModalController.liveCount
                    let subs = window.contentView?.subviews.count ?? 0
                    print("LEAKTEST: cycles=\(total) liveModals=\(live) [expect 0]  windowSubviews=\(subs) baseline=\(baseline) [expect equal]  footprintMB=\(Int(memoryFootprintMB()))")
                    NSApp.terminate(nil)
                }
                return
            }
            let fast = cycle % 3 == 0   // close during the open morph -> exercises cancel()
            let menu = cycle % 5 == 0   // no morphSource + a registered static source -> registry path
            autoreleasepool {
                let modal = DemoModalController(frame: NSMakeRect(0, 0, 320, 380))
                if menu {
                    if let img = ModalMorphTransition.controlImage(controlRef) {
                        ModalMorphContextSource.register(image: img, screenRect: window.convertToScreen(controlRef.convert(controlRef.bounds, to: nil)))
                    }
                    showModal(with: modal, for: window, animated: true)
                } else {
                    showModal(with: modal, for: window, animated: true, morphSource: { [weak controlRef] in controlRef })
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + (fast ? 0.1 : 0.5)) { [weak modal] in
                    modal?.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        cycle += 1
                        runOne()
                    }
                }
            }
        }
        print("LEAKTEST: running \(total) cycles (every 3rd closes during the open morph; every 5th uses the registry)...")
        runOne()
    }

    // Nested modals: open A, then B on top (both morph), then close B. Watches the dimmer via a bright
    // corner patch (shows through the dim), to catch the close-time "disappears-appears-disappears" flicker.
    func runCaptureNested(scale: Double) {
        ModalMorphTransition.durationScale = { scale }
        let window = self.window
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        let patch = View(frame: NSMakeRect(12, 300, 90, 90))   // left edge, away from the centered modals
        patch.backgroundColor = .white
        window.contentView?.addSubview(patch)
        let controlInBar = control
        capturing = true
        captureQueue.async {
            while true {
                self.framesLock.lock(); let on = self.capturing; let ph = self.phase; self.framesLock.unlock()
                if !on { break }
                if let image = self.snapshotNow() {
                    self.framesLock.lock(); let n = self.frames.count; self.frames.append((ph, image)); self.framesLock.unlock()
                    if let dest = CGImageDestinationCreateWithURL(self.outputDir.appendingPathComponent(String(format: "f-%04d-%@.png", n, ph)) as CFURL, "public.png" as CFString, 1, nil) {
                        CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
                    }
                }
                Thread.sleep(forTimeInterval: 0.012)
            }
        }
        var modalB: ModalViewController?
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.framesLock.lock(); self.phase = "openA"; self.framesLock.unlock()
            let a = DemoModalController(frame: NSMakeRect(0, 0, 320, 380))
            a.bgColor = NSColor(calibratedRed: 0.2, green: 0.55, blue: 1, alpha: 1)   // bright so A's content flash is visible
            showModal(with: a, for: window, animated: true, morphSource: { [weak controlInBar] in controlInBar })
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1 * scale) {
                self.framesLock.lock(); self.phase = "openB"; self.framesLock.unlock()
                let b = DemoModalControllerB(frame: NSMakeRect(0, 0, 300, 340))
                modalB = b
                // B morphs from a row INSIDE A (like the wallet transaction row inside the wallet modal),
                // not the shared bar control -> B genuinely morph-closes with A still underneath.
                showModal(with: b, for: window, animated: true, morphSource: { [weak a] in a?.interiorRow })
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1 * scale) {
                    self.framesLock.lock(); self.phase = "closeB"; self.framesLock.unlock()
                    modalB?.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 * scale) {
                        self.framesLock.lock(); self.capturing = false; self.framesLock.unlock()
                        self.captureQueue.sync {}
                        print("NESTED: wrote \(self.frames.count) frames to \(self.outputDir.path)")
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }

    private func writeContactSheet() {
        let open = frames.filter { $0.phase == "open" }.map { $0.image }
        let close = frames.filter { $0.phase == "close" }.map { $0.image }
        let perRow = 14
        func pick(_ arr: [CGImage]) -> [CGImage] {
            guard arr.count > perRow else { return arr }
            return (0 ..< perRow).map { arr[Int(Double($0) / Double(perRow - 1) * Double(arr.count - 1))] }
        }
        let openRow = pick(open), closeRow = pick(close)
        let cellW = 170.0, cellH = 210.0, pad = 30.0
        let cols = Double(max(openRow.count, closeRow.count))
        let W = cols * cellW
        let H = pad + cellH + pad + cellH + pad
        let sheet = NSImage(size: NSMakeSize(W, H))
        sheet.lockFocus()
        NSColor(calibratedWhite: 0.1, alpha: 1).setFill()
        NSBezierPath(rect: NSMakeRect(0, 0, W, H)).fill()
        func drawRow(_ imgs: [CGImage], _ y: Double, _ label: String) {
            NSString(string: label).draw(at: NSMakePoint(8, y + cellH + 4), withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.boldSystemFont(ofSize: 13)])
            for (i, img) in imgs.enumerated() {
                let rect = NSMakeRect(Double(i) * cellW + 6, y, cellW - 12, cellH - 12)
                NSImage(cgImage: img, size: .zero).draw(in: rect)
            }
        }
        drawRow(closeRow, pad, "CLOSE (sheet morphs back to control)")
        drawRow(openRow, pad + cellH + pad, "OPEN (sheet morphs from control; control taken)")
        sheet.unlockFocus()
        if let tiff = sheet.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: outputDir.appendingPathComponent("contact-sheet.png"))
        }
    }
}

func saveCG(_ image: CGImage?, _ path: String) {
    guard let image = image, let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { print("FAIL save \(path)"); return }
    CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
    print("saved \(path) \(image.width)x\(image.height)")
}

func renderLayerToImage(_ view: NSView) -> CGImage? {
    guard let layer = view.layer else { return nil }
    let scale = view.window?.backingScaleFactor ?? 2
    let w = Int(view.bounds.width * scale), h = Int(view.bounds.height * scale)
    guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.scaleBy(x: scale, y: scale)
    layer.render(in: ctx)
    return ctx.makeImage()
}

func cacheDisplayToImage(_ view: NSView) -> CGImage? {
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep.cgImage
}

// Capture-method test: show the modal, then try render(in:)/cacheDisplay/CGWindowList and save each.
final class CapTest {
    static var shared: CapTest?
    let window: Window
    let capture: WindowListCreateImage?
    let outDir: URL
    init(outDir: URL) {
        self.outDir = outDir
        let rect = NSMakeRect(0, 0, 460, 560)
        window = Window(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "CapTest"
        let content = View(frame: rect); content.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1)
        window.contentView = content
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            capture = unsafeBitCast(symbol, to: WindowListCreateImage.self)
        } else { capture = nil }
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    }
    func run() {
        window.makeKeyAndOrderFront(nil); window.orderFrontRegardless()
        let modal = DemoModalController(frame: NSMakeRect(0, 0, 320, 380))
        showModal(with: modal, for: window, animated: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let v = modal.view
            v.layoutSubtreeIfNeeded(); v.displayIfNeeded()
            print("content bounds \(v.bounds), layer \(String(describing: v.layer))")
            saveCG(renderLayerToImage(v), self.outDir.appendingPathComponent("cap-render.png").path)
            saveCG(cacheDisplayToImage(v), self.outDir.appendingPathComponent("cap-cachedisplay.png").path)
            // CGWindowList of the modal's screen rect
            if let cap = self.capture {
                let ns = self.window.convertToScreen(v.convert(v.bounds, to: nil))
                let ph = NSScreen.screens.first?.frame.height ?? ns.maxY
                let cg = CGRect(x: ns.minX, y: ph - ns.maxY, width: ns.width, height: ns.height)
                saveCG(cap(cg, 8, UInt32(self.window.windowNumber), 1)?.takeRetainedValue(), self.outDir.appendingPathComponent("cap-windowlist.png").path)
            }
            print("CapTest done")
            NSApp.terminate(nil)
        }
    }
}

let args = Array(CommandLine.arguments.dropFirst())
let auto = args.first == "auto"
let outArg = auto ? (args.count > 1 ? args[1] : nil) : args.first
let outputDir = URL(fileURLWithPath: outArg ?? (NSTemporaryDirectory() + "modalmorphlab"))

// MARK: Row morph scenario — verifies morphing a TABLE ROW view into a modal and back, including the
// case where the table RELOADS (row view instance replaced) while the modal is open.

private final class DemoRowItem: TableRowItem {
    fileprivate let title: String
    fileprivate let highlighted: Bool
    fileprivate var action: (() -> Void)?
    private let _stableId: AnyHashable
    init(_ initialSize: NSSize, stableId: AnyHashable, title: String, highlighted: Bool) {
        self.title = title
        self.highlighted = highlighted
        self._stableId = stableId
        super.init(initialSize)
    }
    override var stableId: AnyHashable { _stableId }
    override var height: CGFloat { 48 }
    override func viewClass() -> AnyClass { DemoRowView.self }
}

// Visual corner set (mirrors GeneralRows' GeneralViewItemCorners) so the lab can round a subset of corners
// exactly like a first/last/inner list row.
struct LabCorners: OptionSet {
    let rawValue: Int
    static let topLeft = LabCorners(rawValue: 1)
    static let topRight = LabCorners(rawValue: 2)
    static let bottomLeft = LabCorners(rawValue: 4)
    static let bottomRight = LabCorners(rawValue: 8)
    static let all: LabCorners = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

// Which corners the lab's container rounds (toponly / bottomonly args make a first/last-item shape;
// tlonly rounds a single corner with a large radius so the morph's corner mapping is unmistakable).
let labCorners: LabCorners = {
    if CommandLine.arguments.contains("toponly") { return [.topLeft, .topRight] }
    if CommandLine.arguments.contains("bottomonly") { return [.bottomLeft, .bottomRight] }
    if CommandLine.arguments.contains("tlonly") { return [.topLeft] }
    return .all
}()
let labCornerRadius: CGFloat = CommandLine.arguments.contains("tlonly") ? 34 : 16

// Mirrors GeneralRowContainerView: rounds a subset of corners via a CAShapeLayer MASK (not
// layer.cornerRadius), using the SAME flipped arc mapping as GeneralRowContainerView.createMask, and
// reports its radius + corner mask through MorphCornerProviding so the morph can match the shape.
private final class DemoContainer: View, MorphCornerProviding {
    private let maskLayer = CAShapeLayer()
    var cornerRadius: CGFloat = 16
    var corners: LabCorners = .all
    var morphCornerRadius: CGFloat { cornerRadius }
    var morphCorners: CACornerMask {
        if corners == .all { return [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner] }
        var mask: CACornerMask = []
        if corners.contains(.topLeft) { mask.insert(.layerMinXMinYCorner) }
        if corners.contains(.topRight) { mask.insert(.layerMaxXMinYCorner) }
        if corners.contains(.bottomLeft) { mask.insert(.layerMinXMaxYCorner) }
        if corners.contains(.bottomRight) { mask.insert(.layerMaxXMaxYCorner) }
        return mask
    }
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.mask = maskLayer
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        maskLayer.path = DemoContainer.maskPath(corners, bounds, cornerRadius)
    }
    static func maskPath(_ corners: LabCorners, _ frame: CGRect, _ radius: CGFloat) -> CGPath {
        if corners == .all {
            let r = min(frame.height / 2, radius)
            return CGPath(roundedRect: frame, cornerWidth: r, cornerHeight: r, transform: nil)
        }
        var topLeft: CGFloat = 0, bottomLeft: CGFloat = 0, topRight: CGFloat = 0, bottomRight: CGFloat = 0
        if corners.contains(.topLeft) { bottomLeft = radius }
        if corners.contains(.topRight) { bottomRight = radius }
        if corners.contains(.bottomLeft) { topLeft = radius }
        if corners.contains(.bottomRight) { topRight = radius }
        let path = CGMutablePath()
        let minx: CGFloat = 0, midx = frame.width / 2, maxx = frame.width
        let miny: CGFloat = 0, midy = frame.height / 2, maxy = frame.height
        path.move(to: CGPoint(x: minx, y: midy))
        path.addArc(tangent1End: CGPoint(x: minx, y: miny), tangent2End: CGPoint(x: midx, y: miny), radius: bottomLeft)
        path.addArc(tangent1End: CGPoint(x: maxx, y: miny), tangent2End: CGPoint(x: maxx, y: midy), radius: bottomRight)
        path.addArc(tangent1End: CGPoint(x: maxx, y: maxy), tangent2End: CGPoint(x: midx, y: maxy), radius: topRight)
        path.addArc(tangent1End: CGPoint(x: minx, y: maxy), tangent2End: CGPoint(x: minx, y: midy), radius: topLeft)
        return path
    }
}

// A filled rounded bitmap, used as an ImageView's layer `contents` — mirrors the Money row's gem icon and
// NEW badge, which live as image layer content that cacheDisplay drops once the row also has drawn text.
private func solidImage(_ size: NSSize, _ color: NSColor, radius: CGFloat) -> CGImage? {
    let scale: CGFloat = 2
    let w = Int(size.width * scale), h = Int(size.height * scale)
    guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.scaleBy(x: scale, y: scale)
    ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setFillColor(color.cgColor)
    ctx.fillPath()
    return ctx.makeImage()
}

private final class DemoRowView: TableRowView, ViewDisplayDelegate {
    fileprivate let block = DemoContainer(frame: .zero)   // the inset masked "container" (mirrors GeneralRowContainerView)
    private let label = TextView()                          // name is a SUBVIEW (like GeneralInteractedRowView.nameView)
    // The icon + badge are DRAWN into the container's layer via the display delegate (like the Money row's
    // gem thumb and afterNameImage), NOT subviews — this is what cacheDisplay/render(in:) drop on a held row.
    private let iconImage = solidImage(NSMakeSize(22, 22), NSColor(calibratedRed: 0.2, green: 0.55, blue: 1, alpha: 1), radius: 6)
    private let badgeImage = solidImage(NSMakeSize(34, 16), NSColor(calibratedRed: 1, green: 0.3, blue: 0.3, alpha: 1), radius: 5)
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        block.corners = labCorners
        block.cornerRadius = labCornerRadius
        addSubview(block)
        block.addSubview(label)   // content lives INSIDE the container (mirrors GeneralContainableRowView)
        block.displayDelegate = self
    }
    required init?(coder: NSCoder) { fatalError() }
    override var backdorColor: NSColor { NSColor(calibratedWhite: 0.16, alpha: 1) }
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? DemoRowItem else { return }
        block.backgroundColor = item.highlighted ? NSColor(calibratedRed: 0.2, green: 0.55, blue: 1, alpha: 0.9) : NSColor(calibratedWhite: 1, alpha: 0.08)
        let layout = TextViewLayout(.initialize(string: item.title, color: .white, font: .medium(14)))
        layout.measure(width: 300)
        label.update(layout)
        block.needsDisplay = true
        needsLayout = true
    }
    override func draw(_ layer: CALayer, in ctx: CGContext) {
        guard layer == block.layer else { return }
        let h = block.frame.height
        if let iconImage {
            ctx.draw(iconImage, in: NSMakeRect(14, (h - 22) / 2, 22, 22))
        }
        if let badgeImage {
            ctx.draw(badgeImage, in: NSMakeRect(label.frame.maxX + 8, (h - 16) / 2, 34, 16))
        }
    }
    override func layout() {
        super.layout()
        block.frame = NSMakeRect(12, 4, frame.width - 24, frame.height - 8)
        label.setFrameOrigin(NSMakePoint(46, (block.frame.height - label.frame.height) / 2))
        block.needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        (item as? DemoRowItem)?.action?()
    }
}

final class RowLab {
    static var shared: RowLab?
    let window: Window
    let tableView: TableView
    let capture: WindowListCreateImage?
    let outputDir: URL
    private var reloadCount = 0
    private var openModal: DemoModalController?
    init(outputDir: URL) {
        self.outputDir = outputDir
        let rect = NSMakeRect(0, 0, 460, 560)
        window = Window(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ModalMorphLab — rows"
        let content = View(frame: rect)
        content.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 1)
        window.contentView = content
        tableView = TableView(frame: rect)
        content.addSubview(tableView)
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            capture = unsafeBitCast(symbol, to: WindowListCreateImage.self)
        } else { capture = nil }
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }
    func retain() { RowLab.shared = self }

    private func populate() {
        tableView.removeAll()
        var items: [TableRowItem] = []
        let labels = ["General", "Notifications", "Privacy", "Wallet", "Appearance", "Language", "Stickers", "Storage"]
        for (i, name) in labels.enumerated() {
            let wallet = name == "Wallet"
            // Append the reload count so each reload really makes NEW row instances (reload simulation).
            let item = DemoRowItem(tableView.frame.size, stableId: i, title: wallet ? "Wallet  (reload #\(reloadCount))" : name, highlighted: wallet)
            item.action = { [weak self] in self?.openRow(stableId: i) }
            items.append(item)
        }
        tableView.insert(items: items, at: 0)
    }

    // morphSource re-resolves the LIVE row view by stableId — robust to table reloads.
    private func openRow(stableId: AnyHashable) {
        guard openModal == nil else { return }
        let modal = DemoModalController(frame: NSMakeRect(0, 0, 320, 380))
        openModal = modal
        let table = tableView
        showModal(with: modal, for: window, animated: true, morphSource: { [weak table] in
            // Morph from the inset container (the rounded pill), not the full-width row view.
            (table?.item(stableId: stableId)?.view as? DemoRowView)?.block
        })
    }

    func runInteractive(scale: Double) {
        ModalMorphTransition.durationScale = { scale }
        populate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if let m = self.openModal, m.modal == nil { self.openModal = nil }
        }
        print("RowLab: interactive. Click a row (try Wallet). Morph scale \(scale)x.")
    }

    // MARK: capture (reloads the table WHILE the modal is open to prove re-resolution)
    private let captureQueue = DispatchQueue(label: "rowlab.capture", qos: .userInteractive)
    private var capturing = false
    private var phase = "pre"
    private let framesLock = NSLock()
    private var frames: [(String, CGImage)] = []

    func runCapture(scale: Double) {
        ModalMorphTransition.durationScale = { scale }
        populate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        capturing = true
        captureQueue.async {
            while true {
                self.framesLock.lock(); let on = self.capturing; let ph = self.phase; self.framesLock.unlock()
                if !on { break }
                if let cap = self.capture, let image = cap(.null, 8, UInt32(self.window.windowNumber), 1 | 8)?.takeRetainedValue() {
                    self.framesLock.lock(); let n = self.frames.count; self.frames.append((ph, image)); self.framesLock.unlock()
                    if let dest = CGImageDestinationCreateWithURL(self.outputDir.appendingPathComponent(String(format: "r-%04d-%@.png", n, ph)) as CFURL, "public.png" as CFString, 1, nil) {
                        CGImageDestinationAddImage(dest, image, nil); CGImageDestinationFinalize(dest)
                    }
                }
                Thread.sleep(forTimeInterval: 0.012)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.framesLock.lock(); self.phase = "open"; self.framesLock.unlock()
            self.openRow(stableId: 3) // Wallet
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.3 * scale) {
                // Reload the table while the modal is open — new row instances (skip with "noreload").
                self.framesLock.lock(); self.phase = "reload"; self.framesLock.unlock()
                if !CommandLine.arguments.contains("noreload") {
                    self.reloadCount += 1
                    self.populate()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.framesLock.lock(); self.phase = "close"; self.framesLock.unlock()
                    self.openModal?.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4 * scale) {
                        self.framesLock.lock(); self.capturing = false; self.framesLock.unlock()
                        self.captureQueue.sync {}
                        print("RowLab: wrote \(self.frames.count) frames to \(self.outputDir.path)")
                        NSApp.terminate(nil)
                    }
                }
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
System.updateScaleFactor(2)
registerPlaceholderImages()
app.activate(ignoringOtherApps: true)
if args.first == "captest" {
    let out = URL(fileURLWithPath: args.count > 1 ? args[1] : (NSTemporaryDirectory() + "captest"))
    let t = CapTest(outDir: out); CapTest.shared = t
    t.run()
    app.run()
} else if args.first == "row" || args.first == "rowauto" {
    let rowAuto = args.first == "rowauto"
    let out = URL(fileURLWithPath: (rowAuto && args.count > 1) ? args[1] : (NSTemporaryDirectory() + "rowlab"))
    let lab = RowLab(outputDir: out); lab.retain()
    if rowAuto { lab.runCapture(scale: 2.5) } else { lab.runInteractive(scale: args.contains("slow") ? 2.5 : 1.0) }
    app.run()
} else if args.first == "menuauto" {
    let out = URL(fileURLWithPath: args.count > 1 ? args[1] : (NSTemporaryDirectory() + "menulab"))
    let lab = Lab(outputDir: out); lab.retain()
    lab.runCaptureMenu(scale: 2.5)
    app.run()
} else if args.first == "navauto" {
    let out = URL(fileURLWithPath: args.count > 1 ? args[1] : (NSTemporaryDirectory() + "navlab"))
    let lab = Lab(outputDir: out); lab.retain()
    lab.runCaptureNav(scale: 2.5)
    app.run()
} else if args.first == "nestedauto" {
    let out = URL(fileURLWithPath: args.count > 1 ? args[1] : (NSTemporaryDirectory() + "nestedlab"))
    let lab = Lab(outputDir: out); lab.retain()
    lab.runCaptureNested(scale: 2.5)
    app.run()
} else if args.first == "fallbackauto" {
    let out = URL(fileURLWithPath: args.count > 1 ? args[1] : (NSTemporaryDirectory() + "fallbacklab"))
    let lab = Lab(outputDir: out); lab.retain()
    lab.runCaptureFallback(scale: 2.5)
    app.run()
} else if args.first == "ownerauto" {
    let out = URL(fileURLWithPath: args.count > 1 ? args[1] : (NSTemporaryDirectory() + "ownerlab"))
    let lab = Lab(outputDir: out); lab.retain()
    lab.runCaptureOwner(scale: 2.5)
    app.run()
} else if args.first == "leakauto" {
    let lab = Lab(outputDir: URL(fileURLWithPath: NSTemporaryDirectory() + "leaklab")); lab.retain()
    lab.runLeakTest(cycles: args.count > 1 ? (Int(args[1]) ?? 30) : 30)
    app.run()
} else {
    let lab = Lab(outputDir: outputDir)
    lab.retain()
    if auto {
        lab.runCapture(scale: 2.5)
    } else {
        // Real speed by default; pass "slow" for a 2.5x slow-motion inspection.
        lab.runInteractive(scale: args.contains("slow") ? 2.5 : 1.0)
    }
    app.run()
}
