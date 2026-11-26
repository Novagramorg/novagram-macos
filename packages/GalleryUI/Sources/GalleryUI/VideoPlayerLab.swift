#if DEBUG
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramMedia
import TelegramContext
import PerfLab

public enum VideoPlayerLab {
    private static var session: AnyObject?
    private static var didStart = false

    @discardableResult
    public static func startIfRequested(context: any AccountContextProtocol, outputDirectory: URL) -> Bool {
        guard !self.didStart, let configuration = PerfLabConfiguration.fromLaunchArguments(defaultOutputDirectory: outputDirectory), configuration.lab == "video-player" else {
            return false
        }
        self.didStart = true
        Queue.mainQueue().after(configuration.double("-PerfLabStartDelay", 4.0), {
            let session = VideoPlayerLabSession(context: context, configuration: configuration, completion: {
                VideoPlayerLab.session = nil
                if configuration.quitWhenDone {
                    NSApp.terminate(nil)
                }
            })
            VideoPlayerLab.session = session
            session.start()
        })
        return true
    }
}

private struct VideoPlayerLabVideo {
    let message: Message
    let file: TelegramMediaFile
    let isHLS: Bool
    let duration: Double
}

private final class VideoPlayerLabSession {
    private let context: any AccountContextProtocol
    private let configuration: PerfLabConfiguration
    private let completion: () -> Void
    private let report: PerfLabReport
    private let processMonitor = PerfLabProcessMonitor()
    private var loadDisposable: Disposable?
    private var statusDisposable: Disposable?
    private var pending: [(kind: String, video: VideoPlayerLabVideo, index: Int, run: Int)] = []
    private var window: Window?
    private var controller: SVideoController?
    private var latestStatus: MediaPlayerStatus?
    private var latestStatusReceivedAt: Double = 0.0
    private var statusCount = 0
    private var bufferingTotal = 0.0
    private var bufferingStartedAt: Double?
    private var legacyVideos: [VideoPlayerLabVideo] = []
    private lazy var watchdog = VideoPlayerLabWatchdog(outputDirectory: self.configuration.outputDirectory, label: self.configuration.label)

    init(context: any AccountContextProtocol, configuration: PerfLabConfiguration, completion: @escaping () -> Void) {
        self.context = context
        self.configuration = configuration
        self.completion = completion
        self.report = PerfLabReport(configuration: configuration)
    }

    func start() {
        self.watchdog.start()
        let context = self.context
        let channel = self.configuration.string("-PerfLabChannel", "bezposhady")
        let signal: Signal<[Message], NoError> = context.engine.peers.resolvePeerByName(name: channel, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            if case let .result(peer) = result {
                return .single(peer)
            }
            return .complete()
        }
        |> take(1)
        |> mapToSignal { peer -> Signal<[Message], NoError> in
            guard let peer else {
                return .single([])
            }
            return context.engine.messages.searchMessages(location: .peer(peerId: peer.id, fromId: nil, tags: .video, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: "", state: nil, limit: 100)
            |> map { $0.0.messages }
            |> take(1)
        }
        self.loadDisposable = (signal
        |> timeout(30.0, queue: Queue.mainQueue(), alternate: .single([]))
        |> deliverOnMainQueue).start(next: { [weak self] messages in
            self?.didLoad(messages: messages)
        })
    }

    private func didLoad(messages: [Message]) {
        let minDuration = self.configuration.double("-PerfLabMinDuration", 40.0)
        let count = Int(self.configuration.double("-PerfLabVideoCount", 2.0))
        let requestedIds = Set(self.configuration.string("-PerfLabMessageIds", "").split(separator: ",").compactMap { Int32($0) })
        var videos: [VideoPlayerLabVideo] = []
        for message in messages.sorted(by: { $0.id.id > $1.id.id }) {
            if !requestedIds.isEmpty && !requestedIds.contains(message.id.id) {
                continue
            }
            for media in message.media {
                guard let file = media as? TelegramMediaFile, file.isVideo, !file.isAnimated, !file.isInstantVideo, let duration = file.duration, duration >= minDuration else {
                    continue
                }
                videos.append(VideoPlayerLabVideo(message: message, file: file, isHLS: isHLSVideo(file: file), duration: duration))
            }
        }
        NSLog("VideoPlayerLab: %d messages, %d candidate videos (%d HLS)", messages.count, videos.count, videos.filter { $0.isHLS }.count)
        for kind in self.configuration.scenarios {
            if kind.hasPrefix("legacy-") {
                let direct = Array(videos.filter { !$0.isHLS }.prefix(2))
                if direct.isEmpty {
                    self.report.add(scenario: "\(kind)-missing", run: 0, metrics: [:], notes: ["error": "no direct videos"])
                    continue
                }
                for run in 0 ..< self.configuration.runs {
                    self.pending.append((kind, direct[0], 0, run))
                    self.legacyVideos = direct
                }
                continue
            }
            let selected = videos.filter { kind == "hls" ? $0.isHLS : !$0.isHLS }.prefix(count)
            if selected.isEmpty {
                self.report.add(scenario: "\(kind)-missing", run: 0, metrics: [:], notes: ["error": "no \(kind) videos of at least \(Int(minDuration)) s"])
            }
            for (index, video) in selected.enumerated() {
                for run in 0 ..< self.configuration.runs {
                    self.pending.append((kind, video, index, run))
                }
            }
        }
        self.next()
    }

    private func next() {
        guard !self.pending.isEmpty else {
            self.watchdog.stop()
            self.report.add(scenario: "watchdog", run: 0, metrics: ["mainStalls": Double(self.watchdog.stallCount), "worstMainStallSeconds": self.watchdog.worstStall], notes: [:])
            let url = self.report.write()
            NSLog("PerfLab report written to %@", url?.path ?? "nil")
            self.completion()
            return
        }
        let item = self.pending.removeFirst()
        if item.kind.hasPrefix("legacy-") {
            self.runLegacy(kind: item.kind, run: item.run, completion: { [weak self] in
                Queue.mainQueue().after(2.0, {
                    self?.next()
                })
            })
            return
        }
        self.runVideo(kind: item.kind, video: item.video, index: item.index, run: item.run, completion: { [weak self] in
            Queue.mainQueue().after(2.0, {
                self?.next()
            })
        })
    }

    private var player: (UniversalVideoContentView & NSView)? {
        return self.controller?.mediaPlayer
    }

    private func currentPosition() -> Double {
        guard let status = self.latestStatus else {
            return 0.0
        }
        if case .playing = status.status, status.generationTimestamp > 0.0 {
            return status.timestamp + (CACurrentMediaTime() - status.generationTimestamp) * status.baseRate
        }
        return status.timestamp
    }

    private func currentBuffering() -> Double {
        if let bufferingStartedAt = self.bufferingStartedAt {
            return self.bufferingTotal + CACurrentMediaTime() - bufferingStartedAt
        }
        return self.bufferingTotal
    }

    private func isPlayingStatus(after time: Double) -> Bool {
        guard let status = self.latestStatus, self.latestStatusReceivedAt >= time else {
            return false
        }
        if case .playing = status.status {
            return true
        }
        return false
    }

    private func waitUntil(timeout: Double, _ predicate: @escaping () -> Bool, completion: @escaping (Double?) -> Void) {
        let start = CACurrentMediaTime()
        func check() {
            if predicate() {
                completion(CACurrentMediaTime() - start)
            } else if CACurrentMediaTime() - start > timeout {
                completion(nil)
            } else {
                Queue.mainQueue().after(0.05, check)
            }
        }
        check()
    }

    private func measure(_ phase: String, seconds: Double, prefix: String, run: Int, notes: [String: String], extra: [String: Double] = [:], after: (() -> [String: Double])? = nil, completion: @escaping () -> Void) {
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        let startStatusCount = self.statusCount
        let startPosition = self.currentPosition()
        let startBuffering = self.currentBuffering()
        if self.configuration.string("-PerfLabSamplePhase", "") == "\(prefix)-\(phase)" {
            let process = Process()
            process.launchPath = "/usr/bin/sample"
            process.arguments = ["\(ProcessInfo.processInfo.processIdentifier)", "\(max(1, Int(seconds) - 1))", "-file", self.configuration.outputDirectory.appendingPathComponent("video-player-\(self.configuration.label)-\(prefix)-\(phase).sample.txt").path]
            try? process.run()
        }
        Queue.mainQueue().after(seconds, { [weak self] in
            guard let self else {
                return
            }
            let end = self.processMonitor.snapshot()
            let duration = max(0.001, end.time - start.time)
            var metrics: [String: Double] = [
                "duration": duration,
                "cpuCores": (end.cpuTime - start.cpuTime) / duration,
                "mainThreadBusyPercent": (end.mainThreadCpuTime - start.mainThreadCpuTime) / duration * 100,
                "footprintMB": Double(end.footprint) / 1048576.0,
                "statusPerSecond": Double(self.statusCount - startStatusCount) / duration,
                "positionRate": (self.currentPosition() - startPosition) / duration,
                "bufferingSeconds": self.currentBuffering() - startBuffering,
                "startUnixTime": startUnixTime,
                "endUnixTime": Date().timeIntervalSince1970
            ]
            for (key, value) in extra {
                metrics[key] = value
            }
            if let after {
                for (key, value) in after() {
                    metrics[key] = value
                }
            }
            self.report.add(scenario: "\(prefix)-\(phase)", run: run, metrics: metrics, notes: notes)
            completion()
        })
    }

    private func seekAndSettle(_ target: Double, play: Bool, timeout: Double, completion: @escaping (Double?) -> Void) {
        let requestedAt = CACurrentMediaTime()
        self.player?.seek(target, play: play)
        self.waitUntil(timeout: timeout, { [weak self] in
            guard let self else {
                return true
            }
            let position = self.currentPosition()
            return self.isPlayingStatus(after: requestedAt) && position >= target - 0.5 && position <= target + 4.0
        }, completion: completion)
    }

    private func runVideo(kind: String, video: VideoPlayerLabVideo, index: Int, run: Int, completion: @escaping () -> Void) {
        let prefix = "\(kind)\(index)"
        let notes = ["messageId": "\(video.message.id.id)", "duration": String(format: "%.1f", video.duration), "kind": kind]
        let duration = video.duration
        let window = Window(contentRect: NSMakeRect(80, 80, 1280, 720), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Video Player Lab"
        window.isReleasedWhenClosed = false
        guard let contentView = window.contentView else {
            completion()
            return
        }
        let controller = SVideoController(context: self.context, reference: .message(message: MessageReference(video.message), media: video.file), message: video.message)
        let view = controller.genericView
        view.frame = contentView.bounds
        view.autoresizingMask = [.width, .height]
        contentView.addSubview(view)
        window.orderFrontRegardless()
        self.window = window
        self.controller = controller
        self.latestStatus = nil
        self.statusCount = 0
        self.bufferingTotal = 0.0
        self.bufferingStartedAt = nil
        self.statusDisposable = (controller.mediaPlayer.status |> deliverOnMainQueue).start(next: { [weak self] status in
            guard let self else {
                return
            }
            self.statusCount += 1
            self.latestStatus = status
            self.latestStatusReceivedAt = CACurrentMediaTime()
            if case .buffering = status.status {
                if self.bufferingStartedAt == nil {
                    self.bufferingStartedAt = CACurrentMediaTime()
                }
            } else if let bufferingStartedAt = self.bufferingStartedAt {
                self.bufferingTotal += CACurrentMediaTime() - bufferingStartedAt
                self.bufferingStartedAt = nil
            }
        })
        let openStart = self.processMonitor.snapshot()
        let openUnixTime = Date().timeIntervalSince1970
        let openedAt = CACurrentMediaTime()
        controller.play(nil)
        controller.viewDidAppear(false)

        var steps: [(@escaping () -> Void) -> Void] = []

        steps.append({ [weak self] done in
            guard let self else {
                return
            }
            self.waitUntil(timeout: 20.0, { [weak self] in
                guard let self else {
                    return true
                }
                return self.isPlayingStatus(after: openedAt) && self.currentPosition() > 0.1
            }, completion: { [weak self] ttff in
                guard let self else {
                    return
                }
                let end = self.processMonitor.snapshot()
                let elapsed = max(0.001, end.time - openStart.time)
                self.report.add(scenario: "\(prefix)-open", run: run, metrics: [
                    "ttffSeconds": ttff ?? -1.0,
                    "cpuCores": (end.cpuTime - openStart.cpuTime) / elapsed,
                    "mainThreadBusyPercent": (end.mainThreadCpuTime - openStart.mainThreadCpuTime) / elapsed * 100,
                    "footprintMB": Double(end.footprint) / 1048576.0,
                    "startUnixTime": openUnixTime,
                    "endUnixTime": Date().timeIntervalSince1970
                ], notes: notes)
                done()
            })
        })
        steps.append({ [weak self] done in
            self?.measure("play", seconds: 10.0, prefix: prefix, run: run, notes: notes, completion: done)
        })
        steps.append({ [weak self] done in
            guard let self else {
                return
            }
            self.controller?.pause()
            Queue.mainQueue().after(0.5, {
                let position = self.currentPosition()
                self.measure("paused", seconds: 6.0, prefix: prefix, run: run, notes: notes, after: { [weak self] in
                    return ["positionDrift": abs((self?.currentPosition() ?? position) - position)]
                }, completion: done)
            })
        })
        steps.append({ [weak self] done in
            self?.controller?.play()
            self?.measure("resume", seconds: 5.0, prefix: prefix, run: run, notes: notes, completion: done)
        })
        steps.append({ [weak self] done in
            guard let self else {
                return
            }
            let target = duration * 0.5
            self.seekAndSettle(target, play: true, timeout: 15.0, completion: { [weak self] latency in
                guard let self else {
                    return
                }
                let error = abs(self.currentPosition() - target)
                self.measure("seekForward", seconds: 4.0, prefix: prefix, run: run, notes: notes, extra: ["seekLatency": latency ?? -1.0, "seekLandingError": latency == nil ? -1.0 : error], completion: done)
            })
        })
        steps.append({ [weak self] done in
            guard let self else {
                return
            }
            let count = 12
            var issued = 0
            func issue() {
                let fraction = 0.2 + 0.6 * Double(issued) / Double(count - 1)
                self.player?.seek(duration * fraction)
                issued += 1
                if issued < count {
                    Queue.mainQueue().after(0.12, issue)
                } else {
                    let target = duration * 0.8
                    let requestedAt = CACurrentMediaTime()
                    self.waitUntil(timeout: 15.0, { [weak self] in
                        guard let self else {
                            return true
                        }
                        let position = self.currentPosition()
                        return self.isPlayingStatus(after: requestedAt) && position >= target - 0.5 && position <= target + 4.0
                    }, completion: { [weak self] latency in
                        guard let self else {
                            return
                        }
                        let error = abs(self.currentPosition() - target)
                        self.measure("scrub", seconds: 3.0, prefix: prefix, run: run, notes: notes, extra: ["scrubSettleLatency": latency ?? -1.0, "scrubLandingError": latency == nil ? -1.0 : error], completion: done)
                    })
                }
            }
            issue()
        })
        steps.append({ [weak self] done in
            guard let self else {
                return
            }
            let target = duration * 0.1
            self.seekAndSettle(target, play: true, timeout: 15.0, completion: { [weak self] latency in
                guard let self else {
                    return
                }
                self.measure("seekBack", seconds: 3.0, prefix: prefix, run: run, notes: notes, extra: ["seekLatency": latency ?? -1.0, "seekLandingError": latency == nil ? -1.0 : abs(self.currentPosition() - target)], completion: done)
            })
        })
        steps.append({ [weak self] done in
            guard let self else {
                return
            }
            self.player?.setBaseRate(2.0)
            Queue.mainQueue().after(1.0, {
                self.measure("rate2x", seconds: 6.0, prefix: prefix, run: run, notes: notes, completion: {
                    self.player?.setBaseRate(1.0)
                    done()
                })
            })
        })
        steps.append({ [weak self] done in
            guard let self else {
                return
            }
            guard let player = self.player, let qualities = player.videoQualityState(), qualities.available.count > 1, let lowest = qualities.available.min() else {
                done()
                return
            }
            let requestedAt = CACurrentMediaTime()
            let startPosition = self.currentPosition()
            player.setVideoQuality(.quality(lowest))
            self.waitUntil(timeout: 15.0, { [weak self] in
                guard let self else {
                    return true
                }
                return self.isPlayingStatus(after: requestedAt) && self.currentPosition() > startPosition + 0.3
            }, completion: { [weak self] latency in
                guard let self else {
                    return
                }
                let applied = self.player?.videoQualityState()?.current == lowest
                self.measure("quality", seconds: 5.0, prefix: prefix, run: run, notes: notes.merging(["qualities": qualities.available.map { "\($0)" }.joined(separator: "/"), "selected": "\(lowest)"], uniquingKeysWith: { $1 }), extra: ["qualitySwitchLatency": latency ?? -1.0, "qualityApplied": applied ? 1.0 : 0.0, "qualityCount": Double(qualities.available.count)], completion: {
                    self.player?.setVideoQuality(.auto)
                    done()
                })
            })
        })
        steps.append({ [weak self] done in
            guard let self else {
                return
            }
            let requestedAt = CACurrentMediaTime()
            self.player?.seek(max(0.0, duration - 3.0), play: true)
            self.waitUntil(timeout: 15.0, { [weak self] in
                guard let self, let status = self.latestStatus, self.latestStatusReceivedAt >= requestedAt else {
                    return false
                }
                if case .playing = status.status {
                    return false
                }
                return self.currentPosition() >= duration - 1.0
            }, completion: { [weak self] latency in
                guard let self else {
                    return
                }
                var endStatus = -1.0
                if let status = self.latestStatus {
                    switch status.status {
                    case .playing:
                        endStatus = 0.0
                    case .paused:
                        endStatus = 1.0
                    case .buffering:
                        endStatus = 2.0
                    }
                }
                self.measure("afterEnd", seconds: 5.0, prefix: prefix, run: run, notes: notes, extra: ["endLatency": latency ?? -1.0, "reachedEnd": latency == nil ? 0.0 : 1.0, "endPosition": self.currentPosition(), "endStatus": endStatus, "declaredDuration": duration], completion: done)
            })
        })
        steps.append({ [weak self] done in
            guard let self else {
                return
            }
            self.statusDisposable?.dispose()
            self.statusDisposable = nil
            self.controller?.pause()
            self.controller?.viewDidDisappear(false)
            self.controller?.genericView.removeFromSuperview()
            self.controller = nil
            self.window?.orderOut(nil)
            self.window = nil
            self.measure("closed", seconds: 3.0, prefix: prefix, run: run, notes: notes, completion: done)
        })

        func runStep(_ index: Int) {
            guard index < steps.count else {
                completion()
                return
            }
            steps[index]({
                runStep(index + 1)
            })
        }
        runStep(0)
    }
}

private final class VideoPlayerLabWatchdog {
    private let outputDirectory: URL
    private let label: String
    private let queue = DispatchQueue(label: "VideoPlayerLab.watchdog")
    private var timer: DispatchSourceTimer?
    private var pingSentAt: Double?
    private var currentStallStart: Double?
    private var sampledCurrentStall = false
    private(set) var stallCount = 0
    private(set) var worstStall = 0.0

    init(outputDirectory: URL, label: String) {
        self.outputDirectory = outputDirectory
        self.label = label
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: self.queue)
        timer.schedule(deadline: .now() + 0.5, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        self.timer = timer
        timer.resume()
    }

    func stop() {
        self.timer?.cancel()
        self.timer = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        if let pingSentAt = self.pingSentAt {
            let waited = now - pingSentAt
            if waited > 2.5 {
                if self.currentStallStart == nil {
                    self.currentStallStart = pingSentAt
                    self.stallCount += 1
                }
                self.worstStall = max(self.worstStall, waited)
                if !self.sampledCurrentStall {
                    self.sampledCurrentStall = true
                    self.sampleProcess(stallIndex: self.stallCount)
                }
            }
            return
        }
        self.pingSentAt = now
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.queue.async {
                self.pingSentAt = nil
                self.currentStallStart = nil
                self.sampledCurrentStall = false
            }
        }
    }

    private func sampleProcess(stallIndex: Int) {
        try? FileManager.default.createDirectory(at: self.outputDirectory, withIntermediateDirectories: true)
        let path = self.outputDirectory.appendingPathComponent("video-player-\(self.label)-stall\(stallIndex).txt").path
        let process = Process()
        process.launchPath = "/usr/bin/sample"
        process.arguments = ["\(ProcessInfo.processInfo.processIdentifier)", "2", "-file", path]
        try? process.run()
    }
}

extension VideoPlayerLabSession {
    private func makeLegacyPlayer(_ video: VideoPlayerLabVideo, video hasVideo: Bool, sound: Bool, view: MediaPlayerView?) -> MediaPlayer {
        let reference = FileMediaReference.message(message: MessageReference(video.message), media: video.file)
        let player = MediaPlayer(postbox: self.context.account.postbox, userLocation: reference.userLocation, userContentType: reference.userContentType, reference: reference.resourceReference(video.file.resource), streamable: video.file.isStreamable, video: hasVideo, preferSoftwareDecoding: false, enableSound: sound, baseRate: 1.0, volume: 0.3, fetchAutomatically: true)
        if let view {
            player.attachPlayerView(view)
        }
        return player
    }

    private func presentLegacyWindow() -> (Window, MediaPlayerView)? {
        let window = Window(contentRect: NSMakeRect(80, 80, 960, 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Legacy Player Lab"
        window.isReleasedWhenClosed = false
        guard let contentView = window.contentView else {
            return nil
        }
        let view = MediaPlayerView()
        view.frame = contentView.bounds
        view.autoresizingMask = [.width, .height]
        contentView.addSubview(view)
        window.orderFrontRegardless()
        return (window, view)
    }

    private func observeLegacy(_ player: MediaPlayer) -> Disposable {
        self.latestStatus = nil
        self.statusCount = 0
        self.bufferingTotal = 0.0
        self.bufferingStartedAt = nil
        return (player.status |> deliverOnMainQueue).start(next: { [weak self] status in
            guard let self else {
                return
            }
            self.statusCount += 1
            self.latestStatus = status
            self.latestStatusReceivedAt = CACurrentMediaTime()
            if case .buffering = status.status {
                if self.bufferingStartedAt == nil {
                    self.bufferingStartedAt = CACurrentMediaTime()
                }
            } else if let bufferingStartedAt = self.bufferingStartedAt {
                self.bufferingTotal += CACurrentMediaTime() - bufferingStartedAt
                self.bufferingStartedAt = nil
            }
        })
    }

    private func isAdvancing(after time: Double, timeout: Double, completion: @escaping (Double?) -> Void) {
        let startPosition = self.currentPosition()
        self.waitUntil(timeout: timeout, { [weak self] in
            guard let self else {
                return true
            }
            return self.isPlayingStatus(after: time) && self.currentPosition() > startPosition + 0.3
        }, completion: completion)
    }

    fileprivate func runLegacy(kind: String, run: Int, completion: @escaping () -> Void) {
        let videos = self.legacyVideos
        guard let first = videos.first else {
            completion()
            return
        }
        let notes = ["messageId": videos.map { "\($0.message.id.id)" }.joined(separator: ","), "kind": kind]
        switch kind {
        case "legacy-churn":
            self.runLegacyChurn(videos: videos, run: run, notes: notes, completion: completion)
        case "legacy-audio":
            self.runLegacyAudio(video: first, run: run, notes: notes, completion: completion)
        case "legacy-device":
            self.runLegacyDevice(video: first, run: run, notes: notes, completion: completion)
        case "legacy-loop":
            self.runLegacyLoop(video: first, run: run, notes: notes, completion: completion)
        case "legacy-toggle":
            self.runLegacyToggle(video: first, run: run, notes: notes, completion: completion)
        case "legacy-storm":
            self.runLegacyStorm(videos: videos, run: run, notes: notes, completion: completion)
        case "legacy-autoplay":
            self.runLegacyAutoplay(videos: videos, masked: false, run: run, notes: notes, completion: completion)
        case "legacy-autoplay-mask":
            self.runLegacyAutoplay(videos: videos, masked: true, run: run, notes: notes, completion: completion)
        default:
            self.report.add(scenario: "\(kind)-unknown", run: run, metrics: [:], notes: notes)
            completion()
        }
    }

    private func runLegacyChurn(videos: [VideoPlayerLabVideo], run: Int, notes: [String: String], completion: @escaping () -> Void) {
        guard let (window, view) = self.presentLegacyWindow() else {
            completion()
            return
        }
        let count = Int(self.configuration.double("-PerfLabChurnCount", 60.0))
        let lifetimes: [Double] = [0.08, 0.4, 0.15, 0.25, 0.1, 0.35, 0.2, 0.3]
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        let clock = PerfLabFrameClock(view: view)
        clock.start()
        var reachedPlaying = 0
        var created = 0
        func step() {
            guard created < count else {
                clock.stop()
                let end = self.processMonitor.snapshot()
                let duration = max(0.001, end.time - start.time)
                self.report.add(scenario: "legacy-churn", run: run, metrics: [
                    "players": Double(count),
                    "reachedPlaying": Double(reachedPlaying),
                    "seconds": duration,
                    "expectedSeconds": (0 ..< count).reduce(0.0) { $0 + lifetimes[$1 % lifetimes.count] },
                    "cpuCores": (end.cpuTime - start.cpuTime) / duration,
                    "mainThreadBusyPercent": (end.mainThreadCpuTime - start.mainThreadCpuTime) / duration * 100,
                    "footprintMB": Double(end.footprint) / 1048576.0,
                    "hitches": Double(clock.stats.hitches),
                    "worstGapMs": clock.stats.worstGap * 1000,
                    "startUnixTime": startUnixTime,
                    "endUnixTime": Date().timeIntervalSince1970
                ], notes: notes)
                window.orderOut(nil)
                completion()
                return
            }
            let video = videos[created % videos.count]
            let lifetime = lifetimes[created % lifetimes.count]
            created += 1
            var player: MediaPlayer? = self.makeLegacyPlayer(video, video: true, sound: true, view: view)
            var sawPlaying = false
            let disposable = (player!.status |> deliverOnMainQueue).start(next: { status in
                if case .playing = status.status {
                    sawPlaying = true
                }
            })
            player?.seek(timestamp: Double(created % 5) * 3.0, play: true)
            Queue.mainQueue().after(lifetime, {
                if sawPlaying {
                    reachedPlaying += 1
                }
                disposable.dispose()
                player?.pause()
                player = nil
                step()
            })
        }
        step()
    }

    private func runLegacyAudio(video: VideoPlayerLabVideo, run: Int, notes: [String: String], completion: @escaping () -> Void) {
        let player = self.makeLegacyPlayer(video, video: false, sound: true, view: nil)
        player.actionAtEnd = .stop
        let disposable = self.observeLegacy(player)
        let openedAt = CACurrentMediaTime()
        player.play()
        let duration = video.duration
        self.waitUntil(timeout: 15.0, { [weak self] in
            guard let self else {
                return true
            }
            return self.isPlayingStatus(after: openedAt) && self.currentPosition() > 0.1
        }, completion: { [weak self] ttff in
            guard let self else {
                return
            }
            self.report.add(scenario: "legacy-audio-open", run: run, metrics: ["ttffSeconds": ttff ?? -1.0], notes: notes)
            self.measure("play", seconds: 6.0, prefix: "legacy-audio", run: run, notes: notes, completion: {
                player.pause()
                Queue.mainQueue().after(0.5, {
                    let position = self.currentPosition()
                    self.measure("paused", seconds: 4.0, prefix: "legacy-audio", run: run, notes: notes, after: { [weak self] in
                        return ["positionDrift": abs((self?.currentPosition() ?? position) - position)]
                    }, completion: {
                        player.play()
                        self.measure("resume", seconds: 4.0, prefix: "legacy-audio", run: run, notes: notes, completion: {
                            let target = duration * 0.5
                            let requestedAt = CACurrentMediaTime()
                            player.seek(timestamp: target, play: true)
                            self.waitUntil(timeout: 10.0, { [weak self] in
                                guard let self else {
                                    return true
                                }
                                let position = self.currentPosition()
                                return self.isPlayingStatus(after: requestedAt) && position >= target - 0.5 && position <= target + 4.0
                            }, completion: { latency in
                                player.setBaseRate(2.0)
                                self.measure("rate2x", seconds: 4.0, prefix: "legacy-audio", run: run, notes: notes, extra: ["seekLatency": latency ?? -1.0], completion: {
                                    player.setBaseRate(1.0)
                                    let endRequestedAt = CACurrentMediaTime()
                                    player.seek(timestamp: max(0.0, duration - 2.0), play: true)
                                    self.waitUntil(timeout: 10.0, { [weak self] in
                                        guard let self, let status = self.latestStatus, self.latestStatusReceivedAt >= endRequestedAt else {
                                            return false
                                        }
                                        if case .playing = status.status {
                                            return false
                                        }
                                        return self.currentPosition() >= duration - 1.0
                                    }, completion: { endLatency in
                                        self.measure("afterEnd", seconds: 3.0, prefix: "legacy-audio", run: run, notes: notes, extra: ["endLatency": endLatency ?? -1.0, "reachedEnd": endLatency == nil ? 0.0 : 1.0, "endPosition": self.currentPosition()], completion: {
                                            disposable.dispose()
                                            player.pause()
                                            completion()
                                        })
                                    })
                                })
                            })
                        })
                    })
                })
            })
        })
    }

    private func runLegacyDevice(video: VideoPlayerLabVideo, run: Int, notes: [String: String], completion: @escaping () -> Void) {
        guard let (window, view) = self.presentLegacyWindow() else {
            completion()
            return
        }
        let player = self.makeLegacyPlayer(video, video: true, sound: true, view: view)
        let disposable = self.observeLegacy(player)
        let openedAt = CACurrentMediaTime()
        player.play()
        self.isAdvancing(after: openedAt, timeout: 15.0, completion: { [weak self] started in
            guard let self else {
                return
            }
            let beforeBytes = MediaPlayerAudioDebug.renderedBytes
            self.measure("before", seconds: 3.0, prefix: "legacy-device", run: run, notes: notes, extra: ["started": started == nil ? 0.0 : 1.0], after: {
                return ["audioBytesPerSecond": Double(MediaPlayerAudioDebug.renderedBytes - beforeBytes) / 3.0]
            }, completion: {
                var posted = 0
                func post() {
                    let name = posted % 2 == 0 ? AudioNotification.audioOutputDeviceDidChange.notificationName : AudioNotification.mixStereo.notificationName
                    NotificationCenter.default.post(name: name, object: nil)
                    posted += 1
                    if posted < 4 {
                        Queue.mainQueue().after(0.7, post)
                    } else {
                        Queue.mainQueue().after(1.0, {
                            let afterBytes = MediaPlayerAudioDebug.renderedBytes
                            self.measure("after", seconds: 5.0, prefix: "legacy-device", run: run, notes: notes, extra: ["notificationsPosted": Double(posted)], after: {
                                return ["audioBytesPerSecond": Double(MediaPlayerAudioDebug.renderedBytes - afterBytes) / 5.0]
                            }, completion: {
                                disposable.dispose()
                                player.pause()
                                window.orderOut(nil)
                                completion()
                            })
                        })
                    }
                }
                post()
            })
        })
    }

    private func runLegacyLoop(video: VideoPlayerLabVideo, run: Int, notes: [String: String], completion: @escaping () -> Void) {
        guard let (window, view) = self.presentLegacyWindow() else {
            completion()
            return
        }
        let duration = video.duration
        let player = self.makeLegacyPlayer(video, video: true, sound: false, view: view)
        var loops = 0
        player.actionAtEnd = .loop({
            DispatchQueue.main.async {
                loops += 1
            }
        })
        let disposable = self.observeLegacy(player)
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        player.seek(timestamp: max(0.0, duration - 1.5), play: true)
        var attempts = 0
        func check() {
            attempts += 1
            let position = self.currentPosition()
            if loops >= 4 || attempts > 60 {
                let restartedAt = CACurrentMediaTime()
                self.isAdvancing(after: restartedAt, timeout: 5.0, completion: { advancing in
                    let end = self.processMonitor.snapshot()
                    let elapsed = max(0.001, end.time - start.time)
                    self.report.add(scenario: "legacy-loop", run: run, metrics: [
                        "loops": Double(loops),
                        "playingAfterLoops": advancing == nil ? 0.0 : 1.0,
                        "cpuCores": (end.cpuTime - start.cpuTime) / elapsed,
                        "startUnixTime": startUnixTime,
                        "endUnixTime": Date().timeIntervalSince1970
                    ], notes: notes)
                    disposable.dispose()
                    player.pause()
                    window.orderOut(nil)
                    completion()
                })
                return
            }
            if position < duration * 0.5 && position > 0.3 {
                player.seek(timestamp: max(0.0, duration - 1.5), play: true)
            }
            Queue.mainQueue().after(0.25, check)
        }
        Queue.mainQueue().after(0.5, check)
    }

    private func runLegacyToggle(video: VideoPlayerLabVideo, run: Int, notes: [String: String], completion: @escaping () -> Void) {
        guard let (window, view) = self.presentLegacyWindow() else {
            completion()
            return
        }
        let duration = video.duration
        let player = self.makeLegacyPlayer(video, video: true, sound: true, view: view)
        let disposable = self.observeLegacy(player)
        player.play()
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        let clock = PerfLabFrameClock(view: view)
        clock.start()
        var toggles = 0
        func toggle() {
            player.togglePlayPause()
            toggles += 1
            if toggles < 60 {
                Queue.mainQueue().after(0.06, toggle)
            } else {
                var seeks = 0
                func seek() {
                    player.seek(timestamp: duration * (0.1 + 0.8 * Double(seeks % 7) / 7.0))
                    seeks += 1
                    if seeks < 20 {
                        Queue.mainQueue().after(0.05, seek)
                    } else {
                        let requestedAt = CACurrentMediaTime()
                        player.play()
                        self.isAdvancing(after: requestedAt, timeout: 10.0, completion: { recovered in
                            clock.stop()
                            let end = self.processMonitor.snapshot()
                            let elapsed = max(0.001, end.time - start.time)
                            self.report.add(scenario: "legacy-toggle", run: run, metrics: [
                                "recoverSeconds": recovered ?? -1.0,
                                "playingAfterStorm": recovered == nil ? 0.0 : 1.0,
                                "cpuCores": (end.cpuTime - start.cpuTime) / elapsed,
                                "hitches": Double(clock.stats.hitches),
                                "worstGapMs": clock.stats.worstGap * 1000,
                                "startUnixTime": startUnixTime,
                                "endUnixTime": Date().timeIntervalSince1970
                            ], notes: notes)
                            disposable.dispose()
                            player.pause()
                            window.orderOut(nil)
                            completion()
                        })
                    }
                }
                seek()
            }
        }
        Queue.mainQueue().after(1.0, toggle)
    }

    private func runLegacyStorm(videos: [VideoPlayerLabVideo], run: Int, notes: [String: String], completion: @escaping () -> Void) {
        let window = Window(contentRect: NSMakeRect(80, 80, 960, 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Legacy Player Storm"
        window.isReleasedWhenClosed = false
        guard let contentView = window.contentView else {
            completion()
            return
        }
        var views: [MediaPlayerView] = []
        for index in 0 ..< 4 {
            let view = MediaPlayerView()
            view.frame = NSMakeRect(CGFloat(index % 2) * 480, CGFloat(index / 2) * 270, 480, 270)
            contentView.addSubview(view)
            views.append(view)
        }
        window.orderFrontRegardless()
        let seconds = self.configuration.double("-PerfLabStormSeconds", 30.0)
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        let startedAt = CACurrentMediaTime()
        let clock = PerfLabFrameClock(view: contentView)
        clock.start()
        var live: [(player: MediaPlayer, disposable: Disposable, sawStatus: Bool, diesAt: Double)] = []
        var created = 0
        var silent = 0
        var tick = 0
        var lastNotification = startedAt
        let lifetimes: [Double] = [0.05, 0.6, 0.12, 0.3, 0.08, 0.45, 0.2, 0.15, 0.5, 0.1]
        func step() {
            let now = CACurrentMediaTime()
            tick += 1
            var index = 0
            while index < live.count {
                if live[index].diesAt <= now {
                    let entry = live.remove(at: index)
                    if !entry.sawStatus {
                        silent += 1
                    }
                    entry.disposable.dispose()
                    entry.player.pause()
                } else {
                    index += 1
                }
            }
            if now - startedAt >= seconds {
                for entry in live {
                    entry.disposable.dispose()
                    entry.player.pause()
                }
                live.removeAll()
                clock.stop()
                let end = self.processMonitor.snapshot()
                let elapsed = max(0.001, end.time - start.time)
                self.report.add(scenario: "legacy-storm", run: run, metrics: [
                    "playersCreated": Double(created),
                    "playersWithoutStatus": Double(silent),
                    "cpuCores": (end.cpuTime - start.cpuTime) / elapsed,
                    "mainThreadBusyPercent": (end.mainThreadCpuTime - start.mainThreadCpuTime) / elapsed * 100,
                    "footprintMB": Double(end.footprint) / 1048576.0,
                    "hitches": Double(clock.stats.hitches),
                    "worstGapMs": clock.stats.worstGap * 1000,
                    "startUnixTime": startUnixTime,
                    "endUnixTime": Date().timeIntervalSince1970
                ], notes: notes)
                window.orderOut(nil)
                completion()
                return
            }
            if live.count < 8 {
                let video = videos[created % videos.count]
                let hasVideo = created % 2 == 0
                let view = hasVideo ? views[(created / 2) % views.count] : nil
                let player = self.makeLegacyPlayer(video, video: hasVideo, sound: true, view: view)
                let entryIndex = created
                var sawStatus = false
                let disposable = (player.status |> deliverOnMainQueue).start(next: { status in
                    if status.duration > 0.0 {
                        sawStatus = true
                    }
                })
                player.seek(timestamp: Double(entryIndex % 7) * 4.0, play: true)
                live.append((player, disposable, false, now + lifetimes[entryIndex % lifetimes.count]))
                let liveIndex = live.count - 1
                Queue.mainQueue().after(0.04, {
                    if liveIndex < live.count, live[liveIndex].player === player {
                        live[liveIndex].sawStatus = sawStatus
                    }
                })
                created += 1
            }
            for (index, entry) in live.enumerated() {
                switch (tick + index) % 9 {
                case 0:
                    entry.player.togglePlayPause()
                case 3:
                    entry.player.seek(timestamp: Double((tick + index) % 11) * 3.0)
                case 5:
                    entry.player.setBaseRate((tick + index) % 2 == 0 ? 1.5 : 1.0)
                case 7:
                    entry.player.setVolume(Float((tick + index) % 10) / 10.0)
                default:
                    break
                }
            }
            if now - lastNotification >= 0.5 {
                lastNotification = now
                NotificationCenter.default.post(name: tick % 2 == 0 ? AudioNotification.audioOutputDeviceDidChange.notificationName : AudioNotification.mixStereo.notificationName, object: nil)
            }
            Queue.mainQueue().after(0.04, step)
        }
        step()
    }

    private func runLegacyAutoplay(videos: [VideoPlayerLabVideo], masked: Bool, run: Int, notes: [String: String], completion: @escaping () -> Void) {
        let window = Window(contentRect: NSMakeRect(80, 80, 960, 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Legacy Autoplay"
        window.isReleasedWhenClosed = false
        guard let contentView = window.contentView else {
            completion()
            return
        }
        var entries: [(player: MediaPlayer, disposable: Disposable, position: () -> Double, loops: Int)] = []
        var positions: [Double] = Array(repeating: 0.0, count: 6)
        var loopCounts: [Int] = Array(repeating: 0, count: 6)
        for index in 0 ..< 6 {
            let video = videos[index % videos.count]
            let view = MediaPlayerView(backgroundThread: true)
            view.frame = NSMakeRect(CGFloat(index % 3) * 320, CGFloat(index / 3) * 270, 320, 270)
            contentView.addSubview(view)
            if masked {
                view.positionFlags = index % 2 == 0 ? [.top, .left] : [.bottom, .right]
            }
            let reference = FileMediaReference.message(message: MessageReference(video.message), media: video.file)
            let player = MediaPlayer(postbox: self.context.account.postbox, userLocation: reference.userLocation, userContentType: reference.userContentType, reference: reference.resourceReference(video.file.resource), streamable: video.file.isStreamable, video: true, preferSoftwareDecoding: false, enableSound: false, volume: 0.0, fetchAutomatically: true)
            player.attachPlayerView(view)
            player.actionAtEnd = .loop({
                DispatchQueue.main.async {
                    loopCounts[index] += 1
                }
            })
            let disposable = (player.status |> deliverOnMainQueue).start(next: { status in
                var position = status.timestamp
                if case .playing = status.status, status.generationTimestamp > 0.0 {
                    position += CACurrentMediaTime() - status.generationTimestamp
                }
                positions[index] = position
            })
            player.seek(timestamp: max(0.0, video.duration - 3.0 - Double(index) * 0.5), play: true)
            entries.append((player, disposable, { positions[index] }, 0))
        }
        window.orderFrontRegardless()
        Queue.mainQueue().after(3.0, {
            if masked {
                for entry in entries {
                    entry.player.pause()
                }
                Queue.mainQueue().after(0.5, {
                    self.captureLabWindow(window, name: "legacy-autoplay-mask-r\(run)")
                    for entry in entries {
                        entry.player.play()
                    }
                })
            }
            let start = self.processMonitor.snapshot()
            let startUnixTime = Date().timeIntervalSince1970
            let clock = PerfLabFrameClock(view: contentView)
            clock.start()
            Queue.mainQueue().after(12.0, {
                clock.stop()
                let snapshotA = positions
                Queue.mainQueue().after(1.0, {
                    let advancing = zip(snapshotA, positions).filter { $1 > $0 + 0.3 || $1 < $0 - 0.5 }.count
                    let end = self.processMonitor.snapshot()
                    let elapsed = max(0.001, end.time - start.time)
                    self.report.add(scenario: masked ? "legacy-autoplay-mask" : "legacy-autoplay", run: run, metrics: [
                        "players": 6.0,
                        "advancingAtEnd": Double(advancing),
                        "playersThatLooped": Double(loopCounts.filter { $0 > 0 }.count),
                        "totalLoops": Double(loopCounts.reduce(0, +)),
                        "cpuCores": (end.cpuTime - start.cpuTime) / elapsed,
                        "mainThreadBusyPercent": (end.mainThreadCpuTime - start.mainThreadCpuTime) / elapsed * 100,
                        "hitches": Double(clock.stats.hitches),
                        "worstGapMs": clock.stats.worstGap * 1000,
                        "startUnixTime": startUnixTime,
                        "endUnixTime": Date().timeIntervalSince1970
                    ], notes: notes)
                    for entry in entries {
                        entry.disposable.dispose()
                        entry.player.pause()
                    }
                    window.orderOut(nil)
                    completion()
                })
            })
        })
    }

    fileprivate func captureLabWindow(_ window: NSWindow, name: String) {
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) else {
            return
        }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return
        }
        let url = self.configuration.outputDirectory.appendingPathComponent("video-player-\(self.configuration.label)-\(name)-\(width)x\(height).rgba")
        try? Data(bytes).write(to: url)
    }
}
#endif
