import AppKit
import os
import UniformTypeIdentifiers
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import AlertsUI
import TelegramTheme
import Localization
import NovagramCallRecordingCore

public final class NovagramCallRecording {
    public static let shared = NovagramCallRecording()

    private static let screenRecordingSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    private static let log = os.Logger(subsystem: "uz.fenixuz.app", category: "NovagramCallRecording")
    private static let videoSize = CGSize(width: 1280, height: 720)

    private let recordingPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    public private(set) var isRecording = false

    private var capture: AnyObject?
    private var center: AnyObject?
    private var centerDirectory: URL?
    private var session: AnyObject?
    private var activeCallId: UUID?
    private var accessedFolder: URL?
    private var savesToFolder = false
    private var noticePolicy = CallRecordingNoticePolicy()
    private var isStarting = false
    private var stopWhenStarted = false
    private var isMuted = false
    private weak var window: Window?
    private weak var autoWindow: Window?
    private var permissionAlertShown = false
    private var badge: NovagramCallRecordBadgeView?
    private var closeObserver: NSObjectProtocol?
    private let peerDisposable = MetaDisposable()
    private static let quitSaveTimeout: TimeInterval = 3
    private static let quitPollInterval: TimeInterval = 0.05
    private static let peerDataTimeout: Double = 2
    private var pendingStops = 0
    private var isQuitting = false
    private var endedCallIds = Set<UUID>()
    private weak var startingWindow: Window?
    private static let autoStartRetries = 2
    private weak var autoRetryWindow: Window?
    private var autoRetriesLeft = 0
    private let switchDisposable = MetaDisposable()

    public var micDeviceId: () -> Signal<String?, NoError> = { .single(nil) }

    public var recordingSignal: Signal<Bool, NoError> {
        return recordingPromise.get()
    }

    init() {
        switchDisposable.set((NovagramCallRecordingSettings.enabledSignal |> deliverOnMainQueue).start(next: { [weak self] enabled in
            if !enabled {
                self?.recordingSwitchDidTurnOff()
            }
        }))
    }

    private var languageCode: String {
        return appCurrentLanguage.languageCode
    }

    private func recordingSwitchDidTurnOff() {
        autoWindow = nil
        if isStarting {
            stopWhenStarted = true
            return
        }
        guard capture != nil else {
            return
        }
        stop()
    }

    public func toggle(window: Window, engine: TelegramEngine, peerId: PeerId, hasVideo: Bool, callId: UUID?) {
        if isRecording {
            stop()
            return
        }
        guard NovagramCallRecordingSettings.isEnabled else {
            return
        }
        guard #available(macOS 14.0, *), !isStarting else {
            return
        }
        confirmConsent(window: window, proceed: { [weak self, weak window] in
            guard let self, let window, NovagramCallRecordingSettings.isEnabled, window.isVisible, self.isCallActive(callId), self.ensurePermission(window: window) else {
                return
            }
            self.start(window: window, engine: engine, peerId: peerId, hasVideo: hasVideo, isAuto: false, callId: callId)
        })
    }

    public func autoStart(window: Window, engine: TelegramEngine, peerId: PeerId, hasVideo: Bool, callId: UUID?) {
        noteVideoUpgrade(hasVideo: hasVideo)
        guard #available(macOS 14.0, *), NovagramCallRecordingSettings.isAutoEnabled, window.isVisible, autoWindow !== window, capture == nil, !isStarting else {
            return
        }
        if autoRetryWindow !== window {
            autoRetryWindow = window
            autoRetriesLeft = NovagramCallRecording.autoStartRetries
        }
        autoWindow = window
        confirmConsent(window: window, proceed: { [weak self, weak window] in
            guard let self, let window, NovagramCallRecordingSettings.isAutoEnabled, self.autoWindow === window, self.capture == nil, !self.isStarting, self.isCallActive(callId), self.ensurePermission(window: window, isAuto: true) else {
                return
            }
            self.start(window: window, engine: engine, peerId: peerId, hasVideo: hasVideo, isAuto: true, callId: callId)
        }, cancel: {
            NovagramCallRecordingSettings.setAutoEnabled(false)
            NotificationCenter.default.post(name: NSNotification.Name("NovagramSettingsChanged"), object: nil)
        })
    }

    public func callDidUpdate(window: Window?, callId: UUID?, isEnded: Bool, isMuted: Bool) {
        self.isMuted = isMuted
        if isEnded, let window, window === autoWindow {
            autoWindow = nil
        }
        if #available(macOS 14.0, *), let session = session as? CallRecordingSession {
            session.setMuted(isMuted)
        }
        if isEnded, let callId {
            endedCallIds.insert(callId)
            if activeCallId != callId {
                noticePolicy.forget(callSessionId: callId)
            }
        }
        guard isEnded, capture != nil || isStarting else {
            return
        }
        if let window, let own = isStarting ? (startingWindow ?? self.window) : self.window, window !== own {
            return
        }
        if isStarting {
            stopWhenStarted = true
        } else {
            stop()
        }
    }

    private func isCallActive(_ callId: UUID?) -> Bool {
        guard let callId else {
            return false
        }
        return !endedCallIds.contains(callId)
    }

    private var darkTheme: TelegramPresentationTheme {
        return TelegramThemeHooks.shared.darkAppearance()
    }

    private func confirmConsent(window: Window, proceed: @escaping () -> Void, cancel: @escaping () -> Void = {}) {
        guard !NovagramCallRecordingSettings.wasWarned else {
            proceed()
            return
        }
        let l10n = NovagramL10n.current
        verifyAlert(for: window, header: l10n.callRecording_warningTitle, information: l10n.callRecording_warningText, ok: l10n.callRecording_continue, cancel: l10n.callRecording_cancel, successHandler: { _ in
            NovagramCallRecordingSettings.wasWarned = true
            proceed()
        }, cancelHandler: cancel, presentation: darkTheme)
    }

    private func ensurePermission(window: Window, isAuto: Bool = false) -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        let firstRequest = !NovagramCallRecordingSettings.didRequestCapture
        NovagramCallRecordingSettings.didRequestCapture = true
        if CGRequestScreenCaptureAccess() {
            return true
        }
        if firstRequest {
            return false
        }
        if isAuto && permissionAlertShown {
            return false
        }
        permissionAlertShown = true
        showPermissionAlert(window: window)
        return false
    }

    private func showPermissionAlert(window: Window) {
        let l10n = NovagramL10n.current
        verifyAlert_button(for: window, information: l10n.callRecording_permissionText, ok: strings().modalOK, cancel: "", option: l10n.callRecording_openSettings, successHandler: { result in
            if result == .thrid, let url = URL(string: NovagramCallRecording.screenRecordingSettingsURL) {
                NSWorkspace.shared.open(url)
            }
        }, presentation: darkTheme)
    }

    @available(macOS 14.0, *)
    private func start(window: Window, engine: TelegramEngine, peerId: PeerId, hasVideo: Bool, isAuto: Bool, callId: UUID?) {
        isStarting = true
        stopWhenStarted = false
        startingWindow = window
        let peer = engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        let refresh = engine.peers.fetchAndUpdateCachedPeerData(peerId: peerId) |> take(1) |> timeout(NovagramCallRecording.peerDataTimeout, queue: Queue.concurrentDefaultQueue(), alternate: .single(false))
        let messaging = refresh |> mapToSignal { _ in engine.data.get(TelegramEngine.EngineData.Item.Peer.IsBlocked(id: peerId), TelegramEngine.EngineData.Item.Peer.IsPremiumRequiredForMessaging(id: peerId), TelegramEngine.EngineData.Item.Peer.SendPaidMessageStars(id: peerId)) }
        let signal = combineLatest(peer, micDeviceId() |> take(1), messaging) |> take(1) |> deliverOnMainQueue
        peerDisposable.set(signal.start(next: { [weak self, weak window] peer, micDeviceId, messaging in
            guard let self else {
                return
            }
            guard let window, let callId, !self.stopWhenStarted, self.isCallActive(callId) else {
                self.isStarting = false
                return
            }
            let status = self.noticePolicy.status(callSessionId: callId)
            let alreadyNotified = status == .delivered || status == .sending
            guard alreadyNotified || NovagramCallRecording.canNotify(peer: peer, isBlocked: messaging.0, isPremiumRequired: messaging.1, paidStars: messaging.2) else {
                self.isStarting = false
                self.showToast(CallRecordingNoticePolicy.failureMessage(languageCode: self.languageCode))
                return
            }
            self.begin(window: window, title: peer?.debugDisplayTitle ?? "", hasVideo: hasVideo, micDeviceId: micDeviceId, isAuto: isAuto, callId: callId, onStarted: { [weak self] in
                self?.sendNotice(engine: engine, peerId: peerId, callId: callId)
            })
        }))
    }

    @available(macOS 14.0, *)
    private func begin(window: Window, title: String, hasVideo: Bool, micDeviceId: String?, isAuto: Bool, callId: UUID, onStarted: @escaping () -> Void) {
        let capture = NovagramCallCapture(window: window, micDeviceId: micDeviceId, hasVideo: hasVideo)
        capture.onStreamStop = { [weak self, weak capture] in
            guard let self, let capture, self.capture === capture, !self.isStarting else {
                return
            }
            self.stop()
        }
        self.capture = capture
        self.window = window
        capture.start { [weak self, weak window] error in
            guard let self, self.capture === capture else {
                return
            }
            self.isStarting = false
            if let error {
                NovagramCallRecording.log.error("start failed: \(String(describing: error), privacy: .public)")
                self.capture = nil
                if isAuto, let window, self.autoWindow === window, self.autoRetriesLeft > 0 {
                    self.autoRetriesLeft -= 1
                    self.autoWindow = nil
                    return
                }
                self.showToast(NovagramL10n.current.callRecording_failed)
                return
            }
            guard !self.stopWhenStarted else {
                capture.stop()
                self.capture = nil
                return
            }
            guard let session = self.startSession(callId: callId, peerName: title) else {
                capture.stop()
                self.capture = nil
                self.showToast(NovagramL10n.current.callRecording_failed)
                return
            }
            capture.attach(session)
            self.session = session
            self.activeCallId = callId
            self.isRecording = true
            self.recordingPromise.set(true)
            onStarted()
            if let window {
                self.attachBadge(to: window)
            }
            if self.stopWhenStarted {
                self.stop()
            }
        }
    }

    @available(macOS 14.0, *)
    private func startSession(callId: UUID, peerName: String) -> CallRecordingSession? {
        if let folder = NovagramCallRecordingSettings.resolveFolder() {
            let accessing = folder.startAccessingSecurityScopedResource()
            if let session = makeSession(directory: folder, callId: callId, peerName: peerName) {
                accessedFolder = accessing ? folder : nil
                savesToFolder = true
                return session
            }
            if accessing {
                folder.stopAccessingSecurityScopedResource()
            }
        }
        savesToFolder = false
        return makeSession(directory: CallRecordingStorage.defaultDirectory, callId: callId, peerName: peerName)
    }

    @available(macOS 14.0, *)
    private func makeSession(directory: URL, callId: UUID, peerName: String) -> CallRecordingSession? {
        let center: CallRecordingCenter
        if let current = self.center as? CallRecordingCenter, centerDirectory == directory {
            center = current
        } else {
            center = MainActor.assumeIsolated {
                CallRecordingCenter(storage: CallRecordingStorage(directory: directory), configuration: CallRecordingConfiguration(videoSize: NovagramCallRecording.videoSize))
            }
            self.center = center
            self.centerDirectory = directory
        }
        let isMuted = self.isMuted
        do {
            let session = try MainActor.assumeIsolated {
                try center.start(callId: callId, peerName: peerName, onDetach: { [weak self] in
                    self?.sessionDidDetach(callId: callId)
                })
            }
            session.setMuted(isMuted)
            return session
        } catch {
            NovagramCallRecording.log.error("session failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private func sessionDidDetach(callId: UUID) {
        guard #available(macOS 14.0, *), activeCallId == callId, let capture = capture as? NovagramCallCapture else {
            return
        }
        capture.stop()
        self.capture = nil
        session = nil
        activeCallId = nil
        isRecording = false
        recordingPromise.set(false)
        detachBadge()
        releaseFolder(takeAccessedFolder())
        showToast(NovagramL10n.current.callRecording_failed)
    }

    private func takeAccessedFolder() -> URL? {
        let folder = accessedFolder
        accessedFolder = nil
        return folder
    }

    private func releaseFolder(_ folder: URL?) {
        folder?.stopAccessingSecurityScopedResource()
    }

    private static func canNotify(peer: EnginePeer?, isBlocked: EnginePeerCachedInfoItem<Bool>, isPremiumRequired: Bool, paidStars: StarsAmount?) -> Bool {
        guard let peer, peer.id.namespace == Namespaces.Peer.CloudUser, canSendMessagesToPeer(peer) else {
            return false
        }
        return isBlocked.knownValue != true && !isPremiumRequired && (paidStars?.value ?? 0) <= 0
    }

    private func sendNotice(engine: TelegramEngine, peerId: PeerId, callId: UUID) {
        guard noticePolicy.beginSending(callSessionId: callId, isOneToOneUser: peerId.namespace == Namespaces.Peer.CloudUser, recorderDidStart: true) else {
            return
        }
        let current = capture
        let languageCode = self.languageCode
        let message = EnqueueMessage.message(text: CallRecordingNoticePolicy.message(languageCode: languageCode), attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
        let _ = (enqueueMessages(account: engine.account, peerId: peerId, messages: [message]) |> deliverOnMainQueue).start(next: { [weak self] ids in
            guard let self else {
                return
            }
            guard ids.isEmpty || ids.contains(where: { $0 == nil }) else {
                self.noticePolicy.markDelivered(callSessionId: callId)
                return
            }
            #if DEBUG
            NovagramCallRecording.log.error("recording notice was not sent")
            #endif
            self.noticePolicy.markFailed(callSessionId: callId)
            guard let current, self.capture === current else {
                return
            }
            self.stop(discard: true)
            self.showToast(CallRecordingNoticePolicy.failureMessage(languageCode: languageCode))
        })
    }

    private func noteVideoUpgrade(hasVideo: Bool) {
        guard #available(macOS 14.0, *), hasVideo, isRecording, let capture = capture as? NovagramCallCapture else {
            return
        }
        capture.enableVideo()
    }

    private func stop(discard: Bool = false) {
        guard #available(macOS 14.0, *), let capture = capture as? NovagramCallCapture else {
            return
        }
        self.capture = nil
        session = nil
        isRecording = false
        recordingPromise.set(false)
        detachBadge()
        capture.stop()
        let folder = takeAccessedFolder()
        guard let callId = activeCallId, let center = center as? CallRecordingCenter else {
            releaseFolder(folder)
            return
        }
        activeCallId = nil
        let savesToFolder = self.savesToFolder
        pendingStops += 1
        MainActor.assumeIsolated {
            center.stop(callId: callId) { [weak self] result in
                guard let self else {
                    folder?.stopAccessingSecurityScopedResource()
                    return
                }
                self.pendingStops -= 1
                self.recordingDidFinish(result, discard: discard, savesToFolder: savesToFolder, folder: folder)
            }
        }
    }

    @available(macOS 14.0, *)
    private func recordingDidFinish(_ result: Result<URL, CallRecordingError>, discard: Bool, savesToFolder: Bool, folder: URL?) {
        defer {
            releaseFolder(folder)
        }
        switch result {
        case let .success(url):
            if discard {
                if !NovagramCallRecording.discardFile(url) && !NovagramCallRecording.discardFile(url) {
                    NovagramCallRecording.log.error("discarded recording is still on disk: \(url.lastPathComponent, privacy: .public)")
                }
            } else if isQuitting {
                if !savesToFolder {
                    _ = NovagramCallRecording.moveToDownloads(url, fileName: url.lastPathComponent)
                }
            } else if savesToFolder {
                showSaved(url)
            } else {
                askWhereToSave(tempURL: url, fileName: url.lastPathComponent, hasVideo: url.pathExtension.lowercased() == "mp4")
            }
        case let .failure(error):
            NovagramCallRecording.log.error("stop failed: \(String(describing: error), privacy: .public)")
            if !discard && !isQuitting {
                showToast(NovagramL10n.current.callRecording_failed)
            }
        }
    }

    private static func discardFile(_ url: URL) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            log.error("discard failed: \(String(describing: error), privacy: .public)")
            return !FileManager.default.fileExists(atPath: url.path)
        }
    }

    public func stopForQuit() {
        guard #available(macOS 14.0, *) else {
            return
        }
        isQuitting = true
        let deadline = Date().addingTimeInterval(NovagramCallRecording.quitSaveTimeout)
        let allStopped = DispatchSemaphore(value: 0)
        var waitsForAll = false
        var finishQuit: (() -> Void)?
        if let capture = capture as? NovagramCallCapture, let center = center as? CallRecordingCenter {
            self.capture = nil
            session = nil
            activeCallId = nil
            isRecording = false
            detachBadge()
            capture.stop()
            let folder = takeAccessedFolder()
            let storage = CallRecordingStorage(directory: centerDirectory ?? CallRecordingStorage.defaultDirectory)
            let before = Set(storage.list().map { $0.url })
            let savesToFolder = self.savesToFolder
            waitsForAll = true
            MainActor.assumeIsolated {
                center.stopAll(timeout: NovagramCallRecording.quitSaveTimeout) {
                    allStopped.signal()
                }
            }
            finishQuit = {
                if !savesToFolder {
                    for recording in storage.list() where !before.contains(recording.url) {
                        _ = NovagramCallRecording.moveToDownloads(recording.url, fileName: recording.url.lastPathComponent)
                    }
                }
                folder?.stopAccessingSecurityScopedResource()
            }
        }
        while Date() < deadline {
            if waitsForAll, allStopped.wait(timeout: .now()) == .success {
                waitsForAll = false
            }
            if !waitsForAll && pendingStops == 0 {
                break
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(NovagramCallRecording.quitPollInterval))
        }
        finishQuit?()
    }

    private func attachBadge(to window: Window) {
        detachBadge()
        guard window.contentView != nil else {
            return
        }
        let badge = NovagramCallRecordBadgeView()
        badge.place(in: window)
        self.badge = badge
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.stop()
        }
    }

    private func detachBadge() {
        badge?.invalidate()
        badge?.removeFromSuperview()
        badge = nil
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = nil
    }

    private func saveToDownloads(tempURL: URL, fileName: String) {
        if let destination = NovagramCallRecording.moveToDownloads(tempURL, fileName: fileName) {
            showSaved(destination)
        } else {
            showToast(NovagramL10n.current.callRecording_saveFailed)
        }
    }

    private static func move(_ tempURL: URL, to folder: URL, fileName: String) -> URL? {
        let accessing = folder.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                folder.stopAccessingSecurityScopedResource()
            }
        }
        let destination = uniqueURL(in: folder, fileName: fileName)
        do {
            try FileManager.default.moveItem(at: tempURL, to: destination)
            return destination
        } catch {
            log.error("folder save failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func moveToDownloads(_ tempURL: URL, fileName: String) -> URL? {
        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.resolvingSymlinksInPath() else {
            return nil
        }
        return move(tempURL, to: downloads, fileName: fileName)
    }

    private func askWhereToSave(tempURL: URL, fileName: String, hasVideo: Bool) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [hasVideo ? .mpeg4Movie : .mpeg4Audio]
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                self?.saveToDownloads(tempURL: tempURL, fileName: fileName)
                return
            }
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try FileManager.default.moveItem(at: tempURL, to: url)
                self?.showSaved(url)
            } catch {
                NovagramCallRecording.log.error("save failed: \(String(describing: error), privacy: .public)")
                self?.saveToDownloads(tempURL: tempURL, fileName: fileName)
            }
        }
    }

    private func showSaved(_ url: URL) {
        guard let window = toastWindow() else {
            return
        }
        let l10n = NovagramL10n.current
        showModalText(for: window, text: l10n.callRecording_saved, button: l10n.callRecording_showInFinder, callback: { value in
            if value == "action" {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        })
    }

    private func showToast(_ text: String) {
        if let window = toastWindow() {
            showModalText(for: window, text: text)
        }
    }

    private func toastWindow() -> Window? {
        if let window, window.isVisible {
            return window
        }
        if let main = NSApp.mainWindow as? Window {
            return main
        }
        if let key = NSApp.keyWindow as? Window {
            return key
        }
        return NSApp.windows.first(where: { $0.isVisible && $0 is Window }) as? Window
    }

    static func uniqueURL(in folder: URL, fileName: String) -> URL {
        let base = (fileName as NSString).deletingPathExtension
        let fileExtension = (fileName as NSString).pathExtension
        var candidate = folder.appendingPathComponent(fileName)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) (\(index)).\(fileExtension)")
            index += 1
        }
        return candidate
    }
}

final class NovagramCallRecordBadgeView: NSView {
    private static let height: CGFloat = 22
    private static let leftInset: CGFloat = 80
    private static let topInset: CGFloat = 9
    private static let dotSide: CGFloat = 8
    private static let padding: CGFloat = 9
    private static let spacing: CGFloat = 6
    private static let fontSize: CGFloat = 12
    private static let zPosition: CGFloat = 1000
    private static let backgroundAlpha: CGFloat = 0.55

    private let dot = NSView()
    private let label = NSTextField(labelWithString: "")
    private let startDate = Date()
    private var timer: Foundation.Timer?
    private weak var hostWindow: NSWindow?
    private var contentObservation: NSKeyValueObservation?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(NovagramCallRecordBadgeView.backgroundAlpha).cgColor
        layer?.cornerRadius = NovagramCallRecordBadgeView.height / 2
        layer?.zPosition = NovagramCallRecordBadgeView.zPosition
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = NovagramCallRecordBadgeView.dotSide / 2
        label.font = .monospacedDigitSystemFont(ofSize: NovagramCallRecordBadgeView.fontSize, weight: .semibold)
        label.textColor = .white
        addSubview(dot)
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        update()
        let timer = Foundation.Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.update()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    func place(in window: NSWindow) {
        hostWindow = window
        contentObservation = window.observe(\.contentView, options: [.new]) { [weak self] _, _ in
            self?.keepOnTop()
        }
        keepOnTop()
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
        contentObservation?.invalidate()
        contentObservation = nil
        hostWindow = nil
    }

    private func keepOnTop() {
        guard let content = hostWindow?.contentView else {
            return
        }
        if superview !== content || content.subviews.last !== self {
            content.addSubview(self, positioned: .above, relativeTo: nil)
        }
        layout(in: content)
    }

    private func update() {
        let elapsed = Int(Date().timeIntervalSince(startDate))
        let text = String(format: "REC %02d:%02d", elapsed / 60, elapsed % 60)
        label.stringValue = text
        setAccessibilityLabel(text)
        keepOnTop()
    }

    private func layout(in content: NSView) {
        label.sizeToFit()
        let size = NSSize(width: NovagramCallRecordBadgeView.padding * 2 + NovagramCallRecordBadgeView.dotSide + NovagramCallRecordBadgeView.spacing + ceil(label.frame.width), height: NovagramCallRecordBadgeView.height)
        let y = content.isFlipped ? NovagramCallRecordBadgeView.topInset : content.bounds.height - NovagramCallRecordBadgeView.topInset - size.height
        frame = NSRect(origin: NSPoint(x: NovagramCallRecordBadgeView.leftInset, y: y), size: size)
        autoresizingMask = content.isFlipped ? [.maxXMargin, .maxYMargin] : [.maxXMargin, .minYMargin]
        dot.frame = NSRect(x: NovagramCallRecordBadgeView.padding, y: (size.height - NovagramCallRecordBadgeView.dotSide) / 2, width: NovagramCallRecordBadgeView.dotSide, height: NovagramCallRecordBadgeView.dotSide)
        label.frame = NSRect(x: dot.frame.maxX + NovagramCallRecordBadgeView.spacing, y: (size.height - label.frame.height) / 2, width: ceil(label.frame.width), height: label.frame.height)
    }
}
