#if DEBUG
import Cocoa
import Metal
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import CallVideoLayer
import PrivateCallScreen
import AvatarUI
import PerfLab
import TelegramContext
import TelegramTheme
import TelegramVoip
import TgVoipWebrtc

public enum PeerCallLab {
    private static var session: PeerCallLabSession?
    private static var didStart = false

    @discardableResult
    public static func startIfRequested(context: any AccountContextProtocol, outputDirectory: URL) -> Bool {
        guard !self.didStart, let configuration = PerfLabConfiguration.fromLaunchArguments(defaultOutputDirectory: outputDirectory), configuration.lab == "peer-call" else {
            return false
        }
        self.didStart = true
        Queue.mainQueue().after(configuration.double("-PerfLabStartDelay", 4.0), {
            let session = PeerCallLabSession(context: context, configuration: configuration, completion: {
                PeerCallLab.session = nil
                if configuration.quitWhenDone {
                    NSLog("PeerCallLab: quitting")
                    NSApp.terminate(nil)
                    Queue.mainQueue().after(5.0, {
                        NSLog("PeerCallLab: terminate did not exit, forcing exit")
                        exit(0)
                    })
                }
            })
            PeerCallLab.session = session
            session.start()
        })
        return true
    }
}

private final class PeerCallLabSession {
    private let context: any AccountContextProtocol
    private let configuration: PerfLabConfiguration
    private let completion: () -> Void
    private let report: PerfLabReport
    private let processMonitor = PerfLabProcessMonitor()
    private let device = MTLCreateSystemDefaultDevice()

    private let statePromise = ValuePromise<ExternalPeerCallState>(ignoreRepeated: true)
    private let audioLevelPromise = ValuePromise<Float>(0, ignoreRepeated: true)
    private var state: ExternalPeerCallState
    private var screen: PeerCallScreen?
    private var incomingSource: CallVideoLabSource?
    private var outgoingSource: CallVideoLabSource?
    private var audioTimer: SwiftSignalKit.Timer?
    private var nativeCapturer: OngoingCallVideoCapturer?
    private var nativeEvents: [String] = []
    private var steps: [(String, () -> Void)] = []
    private var stepIndex = 0
    private var log: [[String: Any]] = []
    private var pendingScenarios: [String] = []

    init(context: any AccountContextProtocol, configuration: PerfLabConfiguration, completion: @escaping () -> Void) {
        self.context = context
        self.configuration = configuration
        self.completion = completion
        self.report = PerfLabReport(configuration: configuration)
        self.state = ExternalPeerCallState(state: .ringing, videoState: .inactive(true), remoteVideoState: .inactive, isMuted: false, isOutgoingVideoPaused: true, remoteAspectRatio: 1.0, remoteAudioState: .active, remoteBatteryLevel: .normal, isScreenCapture: false, canBeRemoved: false, participants: [], conferenceReference: nil, supportsConferenceCalls: true)
    }

    func start() {
        self.pendingScenarios = self.configuration.scenarios
        self.nextScenario()
    }

    private func nextScenario() {
        guard !self.pendingScenarios.isEmpty else {
            self.finish()
            return
        }
        let scenario = self.pendingScenarios.removeFirst()
        switch scenario {
        case "walkthrough":
            self.runWalkthrough(completion: { [weak self] in
                self?.nextScenario()
            })
        case "perf":
            self.runPerf(completion: { [weak self] in
                self?.nextScenario()
            })
        default:
            NSLog("PeerCallLab: unknown scenario %@", scenario)
            self.nextScenario()
        }
    }

    private func finish() {
        self.audioTimer?.invalidate()
        self.incomingSource?.stop()
        self.outgoingSource?.stop()
        if let data = try? JSONSerialization.data(withJSONObject: self.log, options: [.prettyPrinted, .sortedKeys]) {
            try? FileManager.default.createDirectory(at: self.configuration.outputDirectory, withIntermediateDirectories: true)
            let url = self.configuration.outputDirectory.appendingPathComponent("peer-call-\(self.configuration.label)-steps.json")
            try? data.write(to: url)
            NSLog("PeerCallLab: steps written to %@", url.path)
        }
        let url = self.report.write()
        NSLog("PeerCallLab: report written to %@", url?.path ?? "nil")
        self.completion()
    }

    private func update(_ f: (inout ExternalPeerCallState) -> Void) {
        f(&self.state)
        self.statePromise.set(self.state)
    }

    private func makeSource(width: Int, height: Int, rotation: Float, seed: Int) -> CallVideoLabSource? {
        guard let device = self.device else {
            return nil
        }
        let frames = makeCallVideoLabFrames(width: width, height: height, seed: seed, count: 6)
        let source = CallVideoLabSource(frames: frames, device: device, fps: 30, phase: 0, rotationAngle: rotation, mirrored: false, isStill: false, index: seed)
        source.start()
        return source
    }

    private func openScreen() -> PeerCallScreen {
        let account = self.context.account
        let arguments = PeerCallArguments(engine: self.context.engine, peerId: self.context.peerId, makeAvatar: { view, peer in
            let control = view as? AvatarControl ?? AvatarControl(font: .avatar(17))
            control.setFrameSize(NSMakeSize(120, 120))
            control.userInteractionEnabled = false
            control.setPeer(account: account, peer: peer)
            return control
        }, makeParticipants: { previous, participants in
            let view = (previous as? CallParticipantsView) ?? CallParticipantsView(frame: .zero)
            view.update(participants: participants, account: account, animated: false)
            return view
        }, toggleMute: { [weak self] in
            self?.update { $0.isMuted = !$0.isMuted }
        }, toggleCamera: { [weak self] _ in
            self?.update { state in
                if case .active = state.videoState, !state.isScreenCapture {
                    state.videoState = .inactive(true)
                } else {
                    state.videoState = .active(true)
                    state.isScreenCapture = false
                }
            }
        }, toggleScreencast: { [weak self] _ in
            self?.update { state in
                if case .active = state.videoState, state.isScreenCapture {
                    state.videoState = .inactive(true)
                    state.isScreenCapture = false
                } else {
                    state.videoState = .active(true)
                    state.isScreenCapture = true
                }
            }
        }, endcall: { [weak self] _ in
            self?.update { $0.canBeRemoved = true }
        }, recall: { [weak self] in
            self?.update { $0.state = .requesting(ringing: false) }
        }, acceptcall: { [weak self] in
            self?.update { $0.state = .connecting }
        }, video: { [weak self] isIncoming in
            return isIncoming ? self?.incomingSource : self?.outgoingSource
        }, nativeVideo: { [weak self] _, completion in
            guard let self, isNativeCallVideoRenderingAvailable else {
                completion(nil)
                return
            }
            let capturer: OngoingCallVideoCapturer
            if let current = self.nativeCapturer {
                capturer = current
            } else {
                let sources = DesktopCaptureSourceManagerMac(_s: ()).list()
                self.nativeEvents.append("sources:\(sources.count)")
                if #available(macOS 10.15, *) {
                    self.nativeEvents.append("screenAccess:\(CGPreflightScreenCaptureAccess())")
                }
                guard let source = sources.first else {
                    completion(nil)
                    return
                }
                capturer = OngoingCallVideoCapturer(source.deviceIdKey())
                capturer.setIsVideoEnabled(true)
                self.nativeCapturer = capturer
            }
            capturer.makeOutgoingVideoView(completion: { [weak self] video in
                DispatchQueue.main.async {
                    self?.nativeEvents.append("view:\(video != nil)")
                    let view = video.map { NativeCallVideoView(video: $0) }
                    view?.firstFrameRendered = { [weak self] in
                        self?.nativeEvents.append("firstFrame")
                    }
                    completion(view)
                }
            })
        }, audioLevel: { [weak self] in
            return self?.audioLevelPromise.get() ?? .single(0)
        }, openSettings: { [weak self] window in
            guard let self else {
                return
            }
            showModal(with: CallSettingsModalController(self.context.sharedContext, presentation: TelegramThemeHooks.shared.darkAppearance()), for: window)
        }, upgradeToConference: { _ in
        })
        let screen = PeerCallScreen(external: arguments, isConference: false)
        screen.show()
        screen.setState(self.statePromise.get())
        screen.onCompletion = {
        }
        self.screen = screen
        return screen
    }

    private func setSpeaking(_ speaking: Bool) {
        self.audioTimer?.invalidate()
        self.audioTimer = nil
        if speaking {
            var phase: Double = 0
            let timer = SwiftSignalKit.Timer(timeout: 0.1, repeat: true, completion: { [weak self] in
                phase += 0.7
                self?.audioLevelPromise.set(Float(0.45 + 0.35 * sin(phase)))
            }, queue: .mainQueue())
            self.audioTimer = timer
            timer.start()
        } else {
            self.audioLevelPromise.set(0)
        }
    }

    private func runWalkthrough(completion: @escaping () -> Void) {
        let key = "🐱🐶🐭🐹"
        let now = CFAbsoluteTimeGetCurrent()
        self.state.state = .ringing
        self.state.videoState = .inactive(true)
        self.statePromise.set(self.state)
        _ = self.openScreen()

        self.steps = [
            ("ringing", {}),
            ("ringing-muted", { [weak self] in self?.update { $0.isMuted = true } }),
            ("requesting", { [weak self] in self?.update { $0.isMuted = false; $0.state = .requesting(ringing: true) } }),
            ("connecting", { [weak self] in self?.update { $0.state = .connecting } }),
            ("active", { [weak self] in
                self?.setSpeaking(true)
                self?.update { $0.state = .active(startTime: now, reception: 4, emoji: key) }
            }),
            ("active-muted", { [weak self] in self?.update { $0.isMuted = true } }),
            ("remote-muted", { [weak self] in self?.update { $0.isMuted = false; $0.remoteAudioState = .muted } }),
            ("weak-signal", { [weak self] in self?.update { $0.remoteAudioState = .active; $0.state = .active(startTime: now - 10, reception: 1, emoji: key) } }),
            ("low-battery", { [weak self] in self?.update { $0.state = .active(startTime: now - 10, reception: 4, emoji: key); $0.remoteBatteryLevel = .low } }),
            ("video-outgoing", { [weak self] in
                guard let self else {
                    return
                }
                self.update { $0.remoteBatteryLevel = .normal }
                self.outgoingSource = self.makeSource(width: 1280, height: 720, rotation: 0, seed: 1)
                self.update { $0.videoState = .active(true) }
            }),
            ("video-both", { [weak self] in
                guard let self else {
                    return
                }
                self.incomingSource = self.makeSource(width: 1280, height: 720, rotation: Float.pi * 0.5, seed: 2)
                self.update { $0.remoteVideoState = .active }
            }),
            ("video-swapped", { [weak self] in self?.tapSmallVideo() }),
            ("video-swapped-back", { [weak self] in self?.tapSmallVideo() }),
            ("screencast", { [weak self] in self?.update { $0.isScreenCapture = true } }),
            ("video-off", { [weak self] in
                guard let self else {
                    return
                }
                self.update { $0.isScreenCapture = false; $0.videoState = .inactive(true); $0.remoteVideoState = .inactive }
                self.incomingSource?.stop()
                self.outgoingSource?.stop()
                self.incomingSource = nil
                self.outgoingSource = nil
                self.nativeCapturer = nil
            }),
            ("reconnecting", { [weak self] in self?.update { $0.state = .reconnecting(startTime: now - 10, reception: 0, emoji: key) } }),
            ("busy", { [weak self] in
                self?.setSpeaking(false)
                self?.update { $0.state = .terminated(.ended(.busy)) }
            }),
            ("redial", { [weak self] in self?.update { $0.state = .requesting(ringing: false) } }),
            ("ended", { [weak self] in self?.update { $0.state = .terminated(.ended(.hungUp)) } }),
            ("closed", { [weak self] in self?.update { $0.canBeRemoved = true } }),
            ("released", { [weak self] in self?.checkRelease() }),
            ("released-after-events", { [weak self] in self?.flushEvents() }),
        ]
        self.stepIndex = 0
        self.runNextStep(completion: completion)
    }

    private func runNextStep(completion: @escaping () -> Void) {
        guard self.stepIndex < self.steps.count else {
            completion()
            return
        }
        let (name, action) = self.steps[self.stepIndex]
        let index = self.stepIndex
        self.stepIndex += 1
        action()
        Queue.mainQueue().after(self.configuration.double("-PerfLabStepDelay", 1.4), { [weak self] in
            guard let self else {
                return
            }
            self.recordStep(index: index, name: name)
            self.runNextStep(completion: completion)
        })
    }

    private weak var releasedScreen: PeerCallScreen?
    private weak var releasedWindow: NSWindow?
    
    private var releasedWindowAddress: String?
    
    private func checkRelease() {
        self.releasedScreen = self.screen
        self.releasedWindow = self.screen?.window
        if let window = self.screen?.window {
            self.releasedWindowAddress = "\(Unmanaged.passUnretained(window).toOpaque())"
        }
        self.screen = nil
    }
    
    private func flushEvents() {
        let mainWindow = NSApp.windows.first(where: { $0.isVisible && $0 !== self.releasedWindow })
        for _ in 0 ..< 3 {
            if let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: mainWindow?.windowNumber ?? 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApp.postEvent(event, atStart: false)
            }
        }
        if let mainWindow, let contentView = mainWindow.contentView, let event = NSEvent.mouseEvent(with: .mouseMoved, location: NSMakePoint(contentView.frame.midX, contentView.frame.midY), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: mainWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
            NSApp.postEvent(event, atStart: false)
        }
    }
    
    private func callVideoViews(in view: NSView) -> [CallVideoView] {
        var result: [CallVideoView] = []
        for subview in view.subviews {
            if let video = subview as? CallVideoView {
                result.append(video)
            }
            result.append(contentsOf: self.callVideoViews(in: subview))
        }
        return result
    }

    private func texts(in view: NSView) -> [String] {
        var result: [String] = []
        for subview in view.subviews where !subview.isHidden && subview.alphaValue > 0.01 {
            if let textView = subview as? TextView, let text = textView.textLayout?.attributedString.string, !text.isEmpty {
                result.append(text)
            }
            result.append(contentsOf: self.texts(in: subview))
        }
        return result
    }

    private func classCounts(in view: NSView, into counts: inout [String: Int]) {
        for subview in view.subviews where !subview.isHidden {
            let name = String(describing: type(of: subview))
            if name.hasPrefix("PeerCall") || name.contains("CallVideoView") {
                counts[name, default: 0] += 1
            }
            self.classCounts(in: subview, into: &counts)
        }
    }

    private func tapSmallVideo() {
        guard let contentView = self.screen?.window?.contentView else {
            return
        }
        let videos = self.callVideoViews(in: contentView).filter { $0.superview != nil }
        guard let small = videos.min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }), videos.count > 1 || small.frame.width < contentView.frame.width else {
            return
        }
        small.send(event: .Up)
    }

    private func recordStep(index: Int, name: String) {
        var entry: [String: Any] = ["index": index, "name": name, "native": self.nativeEvents]
        if name == "released" || name == "released-after-events" {
            entry["screenReleased"] = self.releasedScreen == nil
            entry["windowReleased"] = self.releasedWindow == nil
            entry["windowAddress"] = self.releasedWindowAddress ?? ""
            entry["windowInAppList"] = NSApp.windows.contains(where: { $0 === self.releasedWindow })
        }
        if let window = self.screen?.window {
            entry["windowVisible"] = window.isVisible
            if let contentView = window.contentView {
                entry["texts"] = self.texts(in: contentView)
                entry["videos"] = self.callVideoViews(in: contentView).filter { $0.superview != nil }.map { video -> [String: Any] in
                    return ["frame": NSStringFromRect(video.frame), "metrics": video.videoMetrics.map { "\(Int($0.displayResolution.width))x\(Int($0.displayResolution.height))" } ?? "none"]
                }
                var counts: [String: Int] = [:]
                self.classCounts(in: contentView, into: &counts)
                entry["views"] = counts
                if window.isVisible {
                    self.capture(window: window, name: String(format: "%02d-%@", index, name))
                }
            }
        }
        self.log.append(entry)
        NSLog("PeerCallLab step %@: %@", name, "\(entry)")
    }

    private func capture(window: Window, name: String) {
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) else {
            NSLog("PeerCallLab: window capture failed")
            return
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            return
        }
        try? FileManager.default.createDirectory(at: self.configuration.outputDirectory, withIntermediateDirectories: true)
        let url = self.configuration.outputDirectory.appendingPathComponent("peer-call-\(self.configuration.label)-\(name).png")
        try? data.write(to: url)
    }

    private func measure(_ name: String, seconds: Double, notes: [String: String] = [:], completion: @escaping () -> Void) {
        guard let contentView = self.screen?.window?.contentView else {
            completion()
            return
        }
        let clock = PerfLabFrameClock(view: contentView)
        let start = self.processMonitor.snapshot()
        clock.start()
        Queue.mainQueue().after(seconds, { [weak self] in
            guard let self else {
                return
            }
            clock.stop()
            let end = self.processMonitor.snapshot()
            let duration = end.time - start.time
            self.report.add(scenario: name, run: 0, metrics: [
                "duration": duration,
                "cpuCores": duration > 0 ? (end.cpuTime - start.cpuTime) / duration : 0,
                "mainThreadBusyPercent": duration > 0 ? (end.mainThreadCpuTime - start.mainThreadCpuTime) / duration * 100 : 0,
                "footprintMB": Double(end.footprint) / 1048576.0,
                "hitches": Double(clock.stats.hitches),
                "worstGapMs": clock.stats.worstGap * 1000
            ], notes: notes)
            completion()
        })
    }

    private func runPerf(completion: @escaping () -> Void) {
        let seconds = self.configuration.double("-PerfLabSeconds", 10.0)
        let warmup = self.configuration.double("-PerfLabWarmupSeconds", 2.0)
        self.state = ExternalPeerCallState(state: .active(startTime: CFAbsoluteTimeGetCurrent(), reception: 4, emoji: "🐱🐶🐭🐹"), videoState: .inactive(true), remoteVideoState: .inactive, isMuted: false, isOutgoingVideoPaused: true, remoteAspectRatio: 1.0, remoteAudioState: .active, remoteBatteryLevel: .normal, isScreenCapture: false, canBeRemoved: false, participants: [], conferenceReference: nil, supportsConferenceCalls: true)
        self.statePromise.set(self.state)
        let screen = self.openScreen()
        let phases: [(String, () -> Void)] = [
            ("active-silent", { [weak self] in self?.setSpeaking(false) }),
            ("active-speaking", { [weak self] in self?.setSpeaking(true) }),
            ("hidden-speaking", { screen.window?.orderOut(nil) }),
            ("video-both", { [weak self] in
                guard let self else {
                    return
                }
                screen.window?.makeKeyAndOrderFront(nil)
                self.setSpeaking(false)
                self.outgoingSource = self.makeSource(width: 1280, height: 720, rotation: 0, seed: 1)
                self.incomingSource = self.makeSource(width: 1280, height: 720, rotation: 0, seed: 2)
                self.update { $0.videoState = .active(true); $0.remoteVideoState = .active }
            }),
        ]
        var remaining = phases
        func next() {
            guard !remaining.isEmpty else {
                self.setSpeaking(false)
                self.incomingSource?.stop()
                self.outgoingSource?.stop()
                self.incomingSource = nil
                self.outgoingSource = nil
                self.update { $0.videoState = .inactive(true); $0.remoteVideoState = .inactive; $0.canBeRemoved = true }
                Queue.mainQueue().after(1.0, completion)
                return
            }
            let (name, action) = remaining.removeFirst()
            action()
            Queue.mainQueue().after(warmup, { [weak self] in
                guard let self else {
                    return
                }
                self.measure(name, seconds: seconds, notes: ["windowVisible": "\(screen.window?.isVisible ?? false)", "occlusionVisible": "\(screen.window?.occlusionState.contains(.visible) ?? false)"], completion: next)
            })
        }
        next()
    }
}
#endif
