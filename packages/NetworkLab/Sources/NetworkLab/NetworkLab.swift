#if DEBUG
import Foundation
import AppKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramContext
import PerfLab

public enum NetworkLab {
    private static var session: NetworkLabSession?
    private static var didStart = false

    @discardableResult
    public static func startIfRequested<Context: AccountContextProtocol>(context: Context, outputDirectory: URL) -> Bool {
        guard !self.didStart, let configuration = PerfLabConfiguration.fromLaunchArguments(defaultOutputDirectory: outputDirectory), configuration.lab == "network" else {
            return false
        }
        self.didStart = true
        let session = NetworkLabSession(
            accounts: context.sharedContext.activeAccounts |> map { $0.accounts.map { $0.1 } },
            accountManager: context.sharedContext.accountManager,
            engine: context.account.network.engineKind,
            configuration: configuration,
            completion: {
                NetworkLab.session = nil
                if configuration.quitWhenDone {
                    NSApp.terminate(nil)
                }
            }
        )
        self.session = session
        Queue.mainQueue().after(configuration.double("-PerfLabStartDelay", 6.0), {
            session.start()
        })
        return true
    }
}

private struct LabMedia {
    let message: Message
    let media: Media
    let resource: TelegramMediaResource
    let size: Int64
}

private final class LatencyRecorder {
    private(set) var samples: [Double] = []
    private(set) var failures = 0

    func record(_ seconds: Double) {
        self.samples.append(seconds)
    }

    func fail() {
        self.failures += 1
    }

    func percentile(_ value: Double) -> Double {
        guard !self.samples.isEmpty else {
            return 0.0
        }
        let sorted = self.samples.sorted()
        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * value).rounded()))
        return sorted[index] * 1000.0
    }
}

private final class NetworkLabSession {
    private let accounts: Signal<[Account], NoError>
    private let accountManager: AccountManager<TelegramAccountManagerTypes>
    private let engine: NetworkEngineKind
    private let configuration: PerfLabConfiguration
    private let completion: () -> Void
    private let report: PerfLabReport
    private let processMonitor = PerfLabProcessMonitor()
    private let disposables = DisposableSet()
    private var account: Account?
    private var pending: [(scenario: String, run: Int)] = []
    private var heavyPeers: [Peer] = []
    private var loginCodeTimer: SwiftSignalKit.Timer?
    private let backupURL: URL

    init(accounts: Signal<[Account], NoError>, accountManager: AccountManager<TelegramAccountManagerTypes>, engine: NetworkEngineKind, configuration: PerfLabConfiguration, completion: @escaping () -> Void) {
        self.accounts = accounts
        self.accountManager = accountManager
        self.engine = engine
        self.configuration = configuration
        self.completion = completion
        self.report = PerfLabReport(configuration: configuration)
        self.backupURL = configuration.outputDirectory.appendingPathComponent("network-lab-proxy-backup.json")
    }

    func start() {
        try? FileManager.default.createDirectory(at: self.configuration.outputDirectory, withIntermediateDirectories: true)
        self.log("launched with engine \(self.engine.rawValue)")
        let requested = self.configuration.string("-PerfLabNetworkEngine", self.engine.rawValue)
        if let wanted = NetworkEngineKind(rawValue: requested), wanted != self.engine {
            self.log("switching engine \(self.engine.rawValue) -> \(wanted.rawValue); relaunch to continue")
            let marker = self.configuration.outputDirectory.appendingPathComponent("network-lab-engine-switched")
            try? Data(wanted.rawValue.utf8).write(to: marker)
            self.disposables.add((updateNetworkEngineSettings(accountManager: self.accountManager, { _ in NetworkEngineSettings(engine: wanted) }) |> deliverOnMainQueue).start(completed: { [weak self] in
                self?.completion()
            }))
            return
        }
        self.restoreProxyIfNeeded {
            self.applyProxy {
                self.selectAccount()
            }
        }
    }

    private func log(_ text: String) {
        NSLog("NetworkLab: %@", text)
        let url = self.configuration.outputDirectory.appendingPathComponent("network-lab-log.txt")
        let line = "\(Date()) [\(self.configuration.label)] \(text)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            handle.closeFile()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    private func restoreProxyIfNeeded(_ next: @escaping () -> Void) {
        guard let data = try? Data(contentsOf: self.backupURL), let settings = try? JSONDecoder().decode(ProxySettings.self, from: data) else {
            next()
            return
        }
        self.log("restoring proxy settings left by an earlier run")
        self.disposables.add((updateProxySettingsInteractively(accountManager: self.accountManager, { _ in settings }) |> deliverOnMainQueue).start(completed: { [weak self] in
            if let self {
                try? FileManager.default.removeItem(at: self.backupURL)
            }
            next()
        }))
    }

    private func applyProxy(_ next: @escaping () -> Void) {
        let value = self.configuration.string("-PerfLabProxy", "")
        let parts = value.split(separator: ":")
        guard parts.count == 2, let port = Int32(parts[1]) else {
            next()
            return
        }
        let server = ProxyServerSettings(host: String(parts[0]), port: port, connection: .socks5(username: nil, password: nil))
        let backupURL = self.backupURL
        self.disposables.add((self.accountManager.transaction { transaction -> Void in
            let current = transaction.getSharedData(SharedDataKeys.proxySettings)?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
            if let data = try? JSONEncoder().encode(current) {
                try? data.write(to: backupURL)
            }
            _ = updateProxySettingsInteractively(transaction: transaction, { _ in
                ProxySettings(enabled: true, servers: [server], activeServer: server, useForCalls: false)
            })
        } |> deliverOnMainQueue).start(completed: {
            Queue.mainQueue().after(3.0, next)
        }))
    }

    private func restoreProxy(_ next: @escaping () -> Void) {
        guard let data = try? Data(contentsOf: self.backupURL), let settings = try? JSONDecoder().decode(ProxySettings.self, from: data) else {
            next()
            return
        }
        self.disposables.add((updateProxySettingsInteractively(accountManager: self.accountManager, { _ in settings }) |> deliverOnMainQueue).start(completed: { [weak self] in
            if let self {
                try? FileManager.default.removeItem(at: self.backupURL)
            }
            next()
        }))
    }

    private func selectAccount() {
        let wantsTest = self.configuration.string("-PerfLabAccount", "main") == "test"
        self.disposables.add((self.accounts |> filter { !$0.isEmpty } |> take(1) |> deliverOnMainQueue).start(next: { [weak self] accounts in
            guard let self else {
                return
            }
            guard let account = accounts.first(where: { $0.testingEnvironment == wantsTest }) else {
                self.log("no \(wantsTest ? "test" : "production") account is logged in")
                self.finish()
                return
            }
            self.account = account
            self.log("account \(account.peerId.id._internalGetInt64Value()) testing=\(account.testingEnvironment) engine=\(account.network.engineKind.rawValue)")
            for scenario in self.configuration.scenarios {
                for run in 0 ..< self.configuration.runs {
                    self.pending.append((scenario, run))
                }
            }
            if account.testingEnvironment {
                self.disposables.add((account.postbox.transaction { transaction -> String? in
                    (transaction.getPeer(account.peerId) as? TelegramUser)?.phone
                } |> deliverOnMainQueue).start(next: { [weak self] phone in
                    self?.log("test account phone \(phone ?? "unknown")")
                }))
            }
            self.waitOnline { self.loadHeavyPeers { self.next() } }
        }))
    }

    private func waitOnline(_ next: @escaping () -> Void) {
        guard let account = self.account else {
            return
        }
        let started = CFAbsoluteTimeGetCurrent()
        self.disposables.add((account.network.connectionStatus |> filter { status in
            if case .online = status {
                return true
            }
            return false
        } |> take(1) |> timeout(120.0, queue: Queue.mainQueue(), alternate: .single(.waitingForNetwork)) |> deliverOnMainQueue).start(next: { [weak self] _ in
            self?.log("online after \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - started)) s")
            next()
        }))
    }

    private func loadHeavyPeers(_ next: @escaping () -> Void) {
        guard let account = self.account else {
            return
        }
        let limit = Int(self.configuration.double("-PerfLabPeers", 12))
        self.disposables.add((account.postbox.transaction { transaction -> [Peer] in
            let peers = transaction.getChatListPeers(groupId: .root, filterPredicate: nil, additionalFilter: nil)
            let ranked = peers.compactMap { peer -> (Peer, Int32)? in
                guard networkBenchmarkCanRequestHistory(peer: peer), let top = transaction.getTopPeerMessageIndex(peerId: peer.id, namespace: Namespaces.Message.Cloud) else {
                    return nil
                }
                return (peer, top.id.id)
            }
            return ranked.sorted(by: { $0.1 > $1.1 }).prefix(limit).map { $0.0 }
        } |> deliverOnMainQueue).start(next: { [weak self] peers in
            self?.heavyPeers = peers
            self?.log("heavy peers: \(peers.count)")
            next()
        }))
    }

    private func next() {
        guard !self.pending.isEmpty else {
            self.finish()
            return
        }
        let (scenario, run) = self.pending.removeFirst()
        let before = self.processMonitor.snapshot()
        let started = CFAbsoluteTimeGetCurrent()
        self.log("scenario \(scenario) run \(run) on \(self.engine.rawValue)")
        let done: ([String: Double], [String: String]) -> Void = { [weak self] metrics, notes in
            guard let self else {
                return
            }
            let after = self.processMonitor.snapshot()
            var metrics = metrics
            metrics["wall_s"] = CFAbsoluteTimeGetCurrent() - started
            metrics["cpu_s"] = after.cpuTime - before.cpuTime
            metrics["main_thread_cpu_s"] = after.mainThreadCpuTime - before.mainThreadCpuTime
            metrics["footprint_mb"] = Double(after.footprint) / (1024.0 * 1024.0)
            var notes = notes
            notes["engine"] = self.engine.rawValue
            notes["account"] = self.account?.testingEnvironment == true ? "test" : "main"
            notes["proxy"] = self.configuration.string("-PerfLabProxy", "direct")
            self.report.add(scenario: scenario, run: run, metrics: metrics, notes: notes)
            self.log("\(scenario): \(metrics)")
            Queue.mainQueue().after(self.configuration.double("-PerfLabPause", 3.0), { self.next() })
        }
        switch scenario {
        case "chatlist":
            self.runChatList(done)
        case "history":
            self.runHistory(done)
        case "media":
            self.runMedia(done)
        case "bigfile":
            self.runBigFile(done)
        case "upload":
            self.runUpload(done)
        case "catchup":
            self.runCatchup(done)
        case "logincode":
            self.runLoginCode(done)
        default:
            done([:], ["error": "unknown scenario"])
        }
    }

    private func finish() {
        _ = self.report.write()
        self.restoreProxy { [weak self] in
            self?.completion()
        }
    }

    private func timed<T, E>(_ signal: Signal<T, E>, recorder: LatencyRecorder, tag: String = "") -> Signal<T?, NoError> {
        return Signal { [weak self] subscriber in
            let started = CFAbsoluteTimeGetCurrent()
            let wallStarted = Date()
            return signal.start(next: { value in
                let elapsed = CFAbsoluteTimeGetCurrent() - started
                recorder.record(elapsed)
                if elapsed > 2.0 {
                    self?.log("slow request \(tag) \(String(format: "%.2f", elapsed)) s, started \(wallStarted)")
                }
                subscriber.putNext(value)
                subscriber.putCompletion()
            }, error: { error in
                recorder.fail()
                self?.log("failed request \(tag) after \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - started)) s: \(error)")
                subscriber.putNext(nil)
                subscriber.putCompletion()
            })
        }
    }

    private func latencyMetrics(_ recorder: LatencyRecorder, prefix: String) -> [String: Double] {
        return [
            "\(prefix)_requests": Double(recorder.samples.count),
            "\(prefix)_failures": Double(recorder.failures),
            "\(prefix)_p50_ms": recorder.percentile(0.5),
            "\(prefix)_p95_ms": recorder.percentile(0.95),
            "\(prefix)_max_ms": recorder.percentile(1.0),
        ]
    }

    private func runChatList(_ done: @escaping ([String: Double], [String: String]) -> Void) {
        guard let account = self.account else {
            return
        }
        let recorder = LatencyRecorder()
        let requests: [Signal<Int?, NoError>] = (0 ..< 3).flatMap { _ -> [Signal<Int?, NoError>] in
            [
                self.timed(networkBenchmarkRequestDialogs(network: account.network, list: .main), recorder: recorder),
                self.timed(networkBenchmarkRequestDialogs(network: account.network, list: .archive), recorder: recorder),
                self.timed(networkBenchmarkRequestDialogs(network: account.network, list: .pinned), recorder: recorder) |> map { _ in Optional<Int>.none },
            ]
        }
        self.disposables.add((combineLatest(requests) |> deliverOnMainQueue).start(next: { [weak self] results in
            guard let self else {
                return
            }
            let dialogs = results.compactMap { $0 }.reduce(0, +)
            var metrics = self.latencyMetrics(recorder, prefix: "dialogs")
            metrics["dialogs"] = Double(dialogs)
            done(metrics, [:])
        }))
    }

    private func runHistory(_ done: @escaping ([String: Double], [String: String]) -> Void) {
        guard let account = self.account else {
            return
        }
        let recorder = LatencyRecorder()
        let pages = Int(self.configuration.double("-PerfLabPages", 6))
        let perPeer: [Signal<Int, NoError>] = self.heavyPeers.compactMap { peer -> Signal<Int, NoError>? in
            guard networkBenchmarkCanRequestHistory(peer: peer) else {
                return nil
            }
            var chain: Signal<(Int32, Int), NoError> = .single((0, 0))
            for _ in 0 ..< pages {
                chain = chain |> mapToSignal { offsetId, total -> Signal<(Int32, Int), NoError> in
                    if offsetId < 0 {
                        return .single((offsetId, total))
                    }
                    return self.timed(networkBenchmarkRequestHistory(network: account.network, peer: peer, offsetId: offsetId, limit: 100, automaticFloodWait: false), recorder: recorder, tag: "history \(peer.id.id._internalGetInt64Value()) offset \(offsetId)")
                    |> map { result -> (Int32, Int) in
                        let messages = result ?? []
                        let last = messages.map(\.id).min() ?? -1
                        return (messages.isEmpty ? -1 : last, total + messages.count)
                    }
                }
            }
            return chain |> map { $0.1 }
        }
        let concurrency = Int(self.configuration.double("-PerfLabConcurrency", 4))
        var batches: [Signal<[Int], NoError>] = []
        var index = 0
        while index < perPeer.count {
            let slice = Array(perPeer[index ..< min(perPeer.count, index + concurrency)])
            batches.append(combineLatest(slice))
            index += concurrency
        }
        let all = batches.reduce(Signal<Int, NoError>.single(0)) { accumulated, batch in
            accumulated |> mapToSignal { total in
                batch |> map { total + $0.reduce(0, +) }
            }
        }
        self.disposables.add((all |> deliverOnMainQueue).start(next: { [weak self] messages in
            guard let self else {
                return
            }
            var metrics = self.latencyMetrics(recorder, prefix: "history")
            metrics["messages"] = Double(messages)
            metrics["peers"] = Double(self.heavyPeers.count)
            done(metrics, [:])
        }))
    }

    private func collectMedia(account: Account, limit: Int, budget: Int64) -> Signal<[LabMedia], NoError> {
        let peers = self.heavyPeers
        return account.postbox.transaction { transaction -> [LabMedia] in
            var result: [LabMedia] = []
            var total: Int64 = 0
            for peer in peers {
                transaction.scanTopMessages(peerId: peer.id, namespace: Namespaces.Message.Cloud, limit: 400) { message in
                    for media in message.media {
                        if let image = media as? TelegramMediaImage, let largest = largestImageRepresentation(image.representations) {
                            let resource = largest.resource
                            let size = Int64(largest.progressiveSizes.last ?? 0) > 0 ? Int64(largest.progressiveSizes.last!) : (resource.size ?? 150_000)
                            result.append(LabMedia(message: message, media: image, resource: resource, size: size))
                            total += size
                        } else if let file = media as? TelegramMediaFile, let size = file.size, size > 50_000, size < 25_000_000 {
                            result.append(LabMedia(message: message, media: file, resource: file.resource, size: size))
                            total += size
                        }
                    }
                    return result.count < limit && total < budget
                }
                if result.count >= limit || total >= budget {
                    break
                }
            }
            return result
        }
        |> mapToSignal { candidates -> Signal<[LabMedia], NoError> in
            let checks = candidates.map { candidate in
                account.postbox.mediaBox.resourceData(candidate.resource) |> take(1) |> map { data in data.complete ? nil : candidate }
            }
            return combineLatest(checks) |> map { $0.compactMap { $0 } }
        }
    }

    private func runMedia(_ done: @escaping ([String: Double], [String: String]) -> Void) {
        guard let account = self.account else {
            return
        }
        let limit = Int(self.configuration.double("-PerfLabMediaCount", 40))
        let budget = Int64(self.configuration.double("-PerfLabMediaMB", 200)) * 1024 * 1024
        let concurrency = Int(self.configuration.double("-PerfLabConcurrency", 4))
        self.disposables.add((self.collectMedia(account: account, limit: limit, budget: budget) |> deliverOnMainQueue).start(next: { [weak self] items in
            guard let self else {
                return
            }
            let recorder = LatencyRecorder()
            let started = CFAbsoluteTimeGetCurrent()
            var queue = items
            var running = 0
            var completedBytes: Int64 = 0
            var finished = 0
            let fetches = DisposableSet()
            self.disposables.add(fetches)
            func pump() {
                while running < concurrency, !queue.isEmpty {
                    let item = queue.removeFirst()
                    running += 1
                    let itemStarted = CFAbsoluteTimeGetCurrent()
                    let reference: MediaResourceReference
                    if let image = item.media as? TelegramMediaImage {
                        reference = ImageMediaReference.message(message: MessageReference(item.message), media: image).resourceReference(item.resource)
                    } else if let file = item.media as? TelegramMediaFile {
                        reference = FileMediaReference.message(message: MessageReference(item.message), media: file).resourceReference(item.resource)
                    } else {
                        running -= 1
                        continue
                    }
                    let fetch = fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .peer(item.message.id.peerId), userContentType: .file, reference: reference).start()
                    fetches.add(fetch)
                    let wait = (account.postbox.mediaBox.resourceData(item.resource) |> filter { $0.complete } |> take(1) |> map { Optional($0.size) } |> timeout(Double(self.configuration.double("-PerfLabMediaTimeout", 180)), queue: Queue.mainQueue(), alternate: .single(nil)) |> deliverOnMainQueue).start(next: { size in
                        fetch.dispose()
                        running -= 1
                        finished += 1
                        if let size {
                            recorder.record(CFAbsoluteTimeGetCurrent() - itemStarted)
                            completedBytes += size
                        } else {
                            recorder.fail()
                        }
                        if finished == items.count {
                            let elapsed = CFAbsoluteTimeGetCurrent() - started
                            var metrics = self.latencyMetrics(recorder, prefix: "file")
                            metrics["files"] = Double(items.count)
                            metrics["megabytes"] = Double(completedBytes) / (1024.0 * 1024.0)
                            metrics["throughput_mbit"] = elapsed > 0 ? Double(completedBytes) * 8.0 / elapsed / 1_000_000.0 : 0
                            let ids = items.map { $0.resource.id }
                            self.disposables.add((account.postbox.mediaBox.removeCachedResources(ids, force: true) |> deliverOnMainQueue).start(completed: {
                                done(metrics, [:])
                            }))
                        } else {
                            pump()
                        }
                    })
                    fetches.add(wait)
                }
            }
            if items.isEmpty {
                done(["files": 0], ["note": "no uncached media found"])
            } else {
                pump()
            }
        }))
    }

    private func runBigFile(_ done: @escaping ([String: Double], [String: String]) -> Void) {
        guard let account = self.account else {
            return
        }
        let username = self.configuration.string("-PerfLabBigFileChannel", "macos_stable_updates_files")
        let maxSize = Int64(self.configuration.double("-PerfLabBigFileMB", 400)) * 1024 * 1024
        let timeoutSeconds = self.configuration.double("-PerfLabMediaTimeout", 900)
        let engine = TelegramEngine(account: account)
        let target: Signal<(Message, TelegramMediaFile)?, NoError> = engine.peers.resolvePeerByName(name: username, referrer: nil)
        |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            if case let .result(peer) = result {
                return .single(peer)
            }
            return .complete()
        }
        |> take(1)
        |> mapToSignal { peer -> Signal<MessageId?, NoError> in
            guard let peer, networkBenchmarkCanRequestHistory(peer: peer._asPeer()) else {
                return .single(nil)
            }
            return networkBenchmarkRequestHistory(network: account.network, peer: peer._asPeer(), offsetId: 0, limit: 30, automaticFloodWait: false)
            |> map(Optional.init)
            |> `catch` { _ -> Signal<[NetworkBenchmarkHistoryMessage]?, NoError> in
                return .single(nil)
            }
            |> map { result -> MessageId? in
                var best: (id: Int32, size: Int64)?
                for message in result ?? [] {
                    guard let size = message.documentSize else {
                        continue
                    }
                    if size <= maxSize && size > (best?.size ?? 0) {
                        best = (message.id, size)
                    }
                }
                return best.flatMap { MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: $0.id) }
            }
        }
        |> mapToSignal { messageId -> Signal<(Message, TelegramMediaFile)?, NoError> in
            guard let messageId else {
                return .single(nil)
            }
            return engine.messages.downloadMessage(messageId: messageId)
            |> map { message -> (Message, TelegramMediaFile)? in
                guard let message = message?._asMessage(), let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile else {
                    return nil
                }
                return (message, file)
            }
        }
        self.disposables.add((target |> deliverOnMainQueue).start(next: { [weak self] target in
            guard let self else {
                return
            }
            guard let (message, file) = target else {
                done([:], ["error": "no file found in @\(username)"])
                return
            }
            let notes = ["file": file.fileName ?? "", "channel": username]
            self.disposables.add((account.postbox.mediaBox.removeCachedResources([file.resource.id], force: true) |> deliverOnMainQueue).start(completed: { [weak self] in
                guard let self else {
                    return
                }
                let started = CFAbsoluteTimeGetCurrent()
                var firstByte: Double?
                let reference = FileMediaReference.message(message: MessageReference(message), media: file).resourceReference(file.resource)
                let fetch = fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .peer(message.id.peerId), userContentType: .file, reference: reference).start()
                let progress = (account.postbox.mediaBox.resourceStatus(file.resource) |> deliverOnMainQueue).start(next: { status in
                    if firstByte == nil, case let .Fetching(_, value) = status, value > 0 {
                        firstByte = CFAbsoluteTimeGetCurrent() - started
                    }
                })
                let wait = (account.postbox.mediaBox.resourceData(file.resource) |> filter { $0.complete } |> take(1) |> map { Optional($0.size) } |> timeout(timeoutSeconds, queue: Queue.mainQueue(), alternate: .single(nil)) |> deliverOnMainQueue).start(next: { [weak self] size in
                    fetch.dispose()
                    progress.dispose()
                    let elapsed = CFAbsoluteTimeGetCurrent() - started
                    var metrics: [String: Double] = [
                        "file_mb": Double(file.size ?? 0) / (1024.0 * 1024.0),
                        "download_s": size == nil ? -1 : elapsed,
                        "first_progress_s": firstByte ?? -1,
                    ]
                    if let size {
                        metrics["throughput_mbit"] = Double(size) * 8.0 / elapsed / 1_000_000.0
                    }
                    self?.disposables.add((account.postbox.mediaBox.removeCachedResources([file.resource.id], force: true) |> deliverOnMainQueue).start(completed: {
                        done(metrics, notes)
                    }))
                })
                self.disposables.add(fetch)
                self.disposables.add(progress)
                self.disposables.add(wait)
            }))
        }))
    }

    private func runUpload(_ done: @escaping ([String: Double], [String: String]) -> Void) {
        guard let account = self.account else {
            return
        }
        guard account.testingEnvironment else {
            done([:], ["skipped": "uploads run only on the test-environment account"])
            return
        }
        let sizes = self.configuration.string("-PerfLabUploadSizes", "1,1,1,8").split(separator: ",").compactMap { Int($0) }
        let marker = "network-lab-\(self.engine.rawValue)-\(Int(Date().timeIntervalSince1970))"
        let directory = NSTemporaryDirectory()
        var messages: [EnqueueMessage] = []
        var totalBytes = 0
        for (index, megabytes) in sizes.enumerated() {
            let path = directory + "\(marker)-\(index).bin"
            var data = Data(count: megabytes * 1024 * 1024)
            data.withUnsafeMutableBytes { buffer in
                arc4random_buf(buffer.baseAddress!, buffer.count)
            }
            try? data.write(to: URL(fileURLWithPath: path))
            totalBytes += data.count
            let resource = LocalFileReferenceMediaResource(localFilePath: path, randomId: Int64.random(in: Int64.min ... Int64.max), isUniquelyReferencedTemporaryFile: true, size: Int64(data.count))
            let file = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/octet-stream", size: Int64(data.count), attributes: [.FileName(fileName: "\(marker)-\(index).bin")], alternativeRepresentations: [])
            messages.append(.message(text: "\(marker) \(index)", attributes: [], inlineStickers: [:], mediaReference: .standalone(media: file), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: []))
        }
        let peerId = account.peerId
        let started = CFAbsoluteTimeGetCurrent()
        let sent = Signal<[MessageId], NoError> { subscriber in
            let timer = SwiftSignalKit.Timer(timeout: 0.25, repeat: true, completion: {
                _ = account.postbox.transaction({ transaction -> [MessageId] in
                    var found: [MessageId] = []
                    transaction.scanTopMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, limit: 50) { message in
                        if message.text.hasPrefix(marker) {
                            found.append(message.id)
                        }
                        return true
                    }
                    return found
                }).start(next: { found in
                    if found.count >= sizes.count {
                        subscriber.putNext(found)
                        subscriber.putCompletion()
                    }
                })
            }, queue: Queue.mainQueue())
            timer.start()
            return ActionDisposable {
                timer.invalidate()
            }
        }
        self.disposables.add((enqueueMessages(account: account, peerId: peerId, messages: messages) |> mapToSignal { _ in sent } |> timeout(Double(self.configuration.double("-PerfLabUploadTimeout", 600)), queue: Queue.mainQueue(), alternate: .single([])) |> deliverOnMainQueue).start(next: { [weak self] ids in
            guard let self else {
                return
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - started
            var metrics: [String: Double] = [
                "files": Double(sizes.count),
                "uploaded": Double(ids.count),
                "megabytes": Double(totalBytes) / (1024.0 * 1024.0),
            ]
            metrics["throughput_mbit"] = ids.count == sizes.count && elapsed > 0 ? Double(totalBytes) * 8.0 / elapsed / 1_000_000.0 : 0
            self.downloadBack(account: account, ids: ids, completion: { downloadMetrics in
                metrics.merge(downloadMetrics, uniquingKeysWith: { $1 })
                self.disposables.add((TelegramEngine(account: account).messages.deleteMessagesInteractively(messageIds: ids, type: .forEveryone) |> deliverOnMainQueue).start(completed: {
                    done(metrics, [:])
                }))
            })
        }))
    }

    private func runLoginCode(_ done: @escaping ([String: Double], [String: String]) -> Void) {
        guard let account = self.account, account.testingEnvironment else {
            done([:], ["skipped": "login codes are read only on the test-environment account"])
            return
        }
        let service = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(777000))
        let since = Int32(Date().timeIntervalSince1970) - 300
        let url = self.configuration.outputDirectory.appendingPathComponent("network-lab-login-code.txt")
        let waitSeconds = self.configuration.double("-PerfLabCodeTimeout", 180)
        let started = CFAbsoluteTimeGetCurrent()
        let timer = SwiftSignalKit.Timer(timeout: 1.0, repeat: true, completion: { [weak self] in
            _ = account.postbox.transaction({ transaction -> String? in
                var code: String?
                transaction.scanTopMessages(peerId: service, namespace: Namespaces.Message.Cloud, limit: 5) { message in
                    if message.timestamp >= since, let range = message.text.range(of: "[0-9]{5,6}", options: .regularExpression) {
                        code = String(message.text[range])
                        return false
                    }
                    return true
                }
                return code
            }).start(next: { code in
                guard let self else {
                    return
                }
                if let code {
                    try? Data(code.utf8).write(to: url)
                    self.log("login code received")
                    self.loginCodeTimer?.invalidate()
                    self.loginCodeTimer = nil
                    done(["waited_s": CFAbsoluteTimeGetCurrent() - started], [:])
                } else if CFAbsoluteTimeGetCurrent() - started > waitSeconds {
                    self.loginCodeTimer?.invalidate()
                    self.loginCodeTimer = nil
                    done([:], ["error": "no login code"])
                }
            })
        }, queue: Queue.mainQueue())
        self.loginCodeTimer = timer
        timer.start()
    }

    private func downloadBack(account: Account, ids: [MessageId], completion: @escaping ([String: Double]) -> Void) {
        let files = account.postbox.transaction { transaction -> [(Message, TelegramMediaFile)] in
            ids.compactMap { id in
                guard let message = transaction.getMessage(id), let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile else {
                    return nil
                }
                return (message, file)
            }
        }
        self.disposables.add((files |> mapToSignal { files -> Signal<[(Message, TelegramMediaFile)], NoError> in
            account.postbox.mediaBox.removeCachedResources(files.map { $0.1.resource.id }, force: true) |> map { _ in files } |> takeLast
        } |> deliverOnMainQueue).start(next: { [weak self] files in
            guard let self else {
                return
            }
            let started = CFAbsoluteTimeGetCurrent()
            var bytes: Int64 = 0
            let downloads = files.map { message, file -> Signal<Int64, NoError> in
                Signal { subscriber in
                    let reference = FileMediaReference.message(message: MessageReference(message), media: file).resourceReference(file.resource)
                    let fetch = fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .peer(message.id.peerId), userContentType: .file, reference: reference).start()
                    let wait = (account.postbox.mediaBox.resourceData(file.resource) |> filter { $0.complete } |> take(1)).start(next: { data in
                        subscriber.putNext(data.size)
                        subscriber.putCompletion()
                    })
                    return ActionDisposable {
                        fetch.dispose()
                        wait.dispose()
                    }
                }
            }
            self.disposables.add((combineLatest(downloads) |> timeout(600.0, queue: Queue.mainQueue(), alternate: .single([])) |> deliverOnMainQueue).start(next: { sizes in
                bytes = sizes.reduce(0, +)
                let elapsed = CFAbsoluteTimeGetCurrent() - started
                completion([
                    "download_s": sizes.isEmpty ? -1 : elapsed,
                    "download_mbit": elapsed > 0 ? Double(bytes) * 8.0 / elapsed / 1_000_000.0 : 0,
                ])
            }))
        }))
    }

    private func runCatchup(_ done: @escaping ([String: Double], [String: String]) -> Void) {
        guard let account = self.account else {
            return
        }
        let back = Int32(self.configuration.double("-PerfLabPtsBack", 3000))
        let days = Int32(self.configuration.double("-PerfLabDaysBack", 3))
        self.disposables.add((account.postbox.transaction { transaction -> (Int32, Int32)? in
            guard let state = transaction.getState() as? AuthorizedAccountState, let current = state.state else {
                return nil
            }
            let rewound = AuthorizedAccountState.State(pts: max(1, current.pts - back), qts: current.qts, date: current.date - days * 86_400, seq: current.seq)
            transaction.setState(state.changedState(rewound))
            return (current.pts, rewound.pts)
        } |> deliverOnMainQueue).start(next: { [weak self] values in
            guard let self, let (original, rewound) = values else {
                done([:], ["error": "no account state"])
                return
            }
            let started = CFAbsoluteTimeGetCurrent()
            account.resetStateManagement()
            let polling = Signal<Int32, NoError> { subscriber in
                let timer = SwiftSignalKit.Timer(timeout: 0.5, repeat: true, completion: {
                    _ = account.postbox.transaction({ transaction -> Int32 in
                        (transaction.getState() as? AuthorizedAccountState)?.state?.pts ?? 0
                    }).start(next: { pts in
                        if pts >= original {
                            subscriber.putNext(pts)
                            subscriber.putCompletion()
                        }
                    })
                }, queue: Queue.mainQueue())
                timer.start()
                return ActionDisposable {
                    timer.invalidate()
                }
            }
            let timeoutSeconds = self.configuration.double("-PerfLabCatchupTimeout", 600)
            self.disposables.add((polling |> take(1) |> timeout(timeoutSeconds, queue: Queue.mainQueue(), alternate: .single(-1)) |> deliverOnMainQueue).start(next: { pts in
                let elapsed = CFAbsoluteTimeGetCurrent() - started
                done([
                    "pts_rewound": Double(original - rewound),
                    "catchup_s": pts >= 0 ? elapsed : -1,
                    "final_pts": Double(pts),
                ], [:])
            }))
        }))
    }
}
#endif
