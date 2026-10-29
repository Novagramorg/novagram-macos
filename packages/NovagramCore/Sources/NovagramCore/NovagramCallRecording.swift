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

// Local 1:1 call recording: the call screen's Record button (PrivateCallScreen NovagramCallRecordHooks) lands here.
// Everything runs on the main thread except the recorder's own capture queue.
public final class NovagramCallRecording {
    public static let shared = NovagramCallRecording()

    private static let screenRecordingSettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    private static let fileDateFormat = "yyyy-MM-dd HH.mm"
    private static let fallbackFileName = "Novagram call"
    private static let log = os.Logger(subsystem: "uz.fenixuz.app", category: "NovagramCallRecording")

    private let recordingPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
    public private(set) var isRecording = false

    private var recorder: AnyObject?
    private var isStarting = false
    private var stopWhenStarted = false
    private var isMuted = false
    private var fileName = ""
    private weak var window: Window?
    private var badge: NovagramCallRecordBadgeView?
    private var closeObserver: NSObjectProtocol?
    private let peerDisposable = MetaDisposable()

    public var recordingSignal: Signal<Bool, NoError> {
        return recordingPromise.get()
    }

    public func toggle(window: Window, engine: TelegramEngine, peerId: PeerId, hasVideo: Bool) {
        if isRecording {
            stop()
            return
        }
        guard #available(macOS 14.0, *), !isStarting else {
            return
        }
        confirmConsent(window: window) { [weak self, weak window] in
            guard let self, let window, self.ensurePermission(window: window) else {
                return
            }
            self.start(window: window, engine: engine, peerId: peerId, hasVideo: hasVideo)
        }
    }

    public func callDidUpdate(window: Window?, isEnded: Bool, isMuted: Bool) {
        self.isMuted = isMuted
        if #available(macOS 14.0, *), let recorder = recorder as? NovagramCallRecorder {
            recorder.setMicMuted(isMuted)
        }
        guard isEnded, recorder != nil else {
            return
        }
        if let window, let own = self.window, window !== own {
            return
        }
        if isStarting {
            stopWhenStarted = true
        } else {
            stop()
        }
    }

    private var darkTheme: TelegramPresentationTheme {
        return TelegramThemeHooks.shared.darkAppearance()
    }

    private func confirmConsent(window: Window, proceed: @escaping () -> Void) {
        guard !NovagramCallRecordingSettings.wasWarned else {
            proceed()
            return
        }
        let l10n = NovagramL10n.current
        verifyAlert(for: window, header: l10n.callRecording_warningTitle, information: l10n.callRecording_warningText, ok: l10n.callRecording_continue, cancel: l10n.callRecording_cancel, successHandler: { _ in
            NovagramCallRecordingSettings.wasWarned = true
            proceed()
        }, presentation: darkTheme)
    }

    private func ensurePermission(window: Window) -> Bool {
        if CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() {
            return true
        }
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
    private func start(window: Window, engine: TelegramEngine, peerId: PeerId, hasVideo: Bool) {
        isStarting = true
        stopWhenStarted = false
        let peer = engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)) |> deliverOnMainQueue
        peerDisposable.set(peer.start(next: { [weak self, weak window] peer in
            guard let self else {
                return
            }
            guard let window else {
                self.isStarting = false
                return
            }
            self.begin(window: window, title: peer?.debugDisplayTitle ?? "", hasVideo: hasVideo)
        }))
    }

    @available(macOS 14.0, *)
    private func begin(window: Window, title: String, hasVideo: Bool) {
        let fileExtension = hasVideo ? "mp4" : "m4a"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("novagram-call-\(UUID().uuidString).\(fileExtension)")
        let recorder = NovagramCallRecorder(outputURL: tempURL, hasVideo: hasVideo, window: window)
        recorder.setMicMuted(isMuted)
        recorder.onStreamStop = { [weak self, weak recorder] in
            guard let self, let recorder, self.recorder === recorder, !self.isStarting else {
                return
            }
            self.stop()
        }
        self.recorder = recorder
        self.window = window
        self.fileName = NovagramCallRecording.fileName(title: title, fileExtension: fileExtension)
        recorder.start { [weak self, weak window] error in
            guard let self, self.recorder === recorder else {
                return
            }
            self.isStarting = false
            if let error {
                NovagramCallRecording.log.error("start failed: \(String(describing: error), privacy: .public)")
                self.recorder = nil
                self.showToast(NovagramL10n.current.callRecording_failed)
                return
            }
            self.isRecording = true
            self.recordingPromise.set(true)
            if let window {
                self.attachBadge(to: window)
            }
            if self.stopWhenStarted {
                self.stop()
            }
        }
    }

    private func stop() {
        guard #available(macOS 14.0, *), let recorder = recorder as? NovagramCallRecorder else {
            return
        }
        self.recorder = nil
        isRecording = false
        recordingPromise.set(false)
        detachBadge()
        let fileName = self.fileName
        recorder.stop { [weak self] result in
            switch result {
            case let .success(url):
                self?.save(tempURL: url, fileName: fileName, hasVideo: recorder.hasVideo)
            case let .failure(error):
                NovagramCallRecording.log.error("stop failed: \(String(describing: error), privacy: .public)")
                self?.showToast(NovagramL10n.current.callRecording_failed)
            }
        }
    }

    private func attachBadge(to window: Window) {
        detachBadge()
        guard let content = window.contentView else {
            return
        }
        let badge = NovagramCallRecordBadgeView()
        badge.place(in: content)
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

    private func save(tempURL: URL, fileName: String, hasVideo: Bool) {
        if let folder = NovagramCallRecordingSettings.resolveFolder() {
            let accessing = folder.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    folder.stopAccessingSecurityScopedResource()
                }
            }
            let destination = NovagramCallRecording.uniqueURL(in: folder, fileName: fileName)
            do {
                try FileManager.default.moveItem(at: tempURL, to: destination)
                showSaved(destination)
                return
            } catch {
                NovagramCallRecording.log.error("folder save failed: \(String(describing: error), privacy: .public)")
            }
        }
        askWhereToSave(tempURL: tempURL, fileName: fileName, hasVideo: hasVideo)
    }

    private func askWhereToSave(tempURL: URL, fileName: String, hasVideo: Bool) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = fileName
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [hasVideo ? .mpeg4Movie : .mpeg4Audio]
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                try? FileManager.default.removeItem(at: tempURL)
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
                try? FileManager.default.removeItem(at: tempURL)
                self?.showToast(NovagramL10n.current.callRecording_saveFailed)
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

    static func fileName(title: String, fileExtension: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = fileDateFormat
        let cleaned = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleaned.isEmpty ? fallbackFileName : cleaned
        return "\(name) \(formatter.string(from: Date())).\(fileExtension)"
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

    func place(in content: NSView) {
        content.addSubview(self)
        layout(in: content)
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }

    private func update() {
        let elapsed = Int(Date().timeIntervalSince(startDate))
        let text = String(format: "REC %02d:%02d", elapsed / 60, elapsed % 60)
        label.stringValue = text
        setAccessibilityLabel(text)
        if let content = superview {
            layout(in: content)
        }
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
