import Cocoa
import SwiftUI
import TGUIKit
import SwiftSignalKit
import TelegramTheme
import Localization
import NovagramCallRecordingCore
import NovagramCallRecordingUI

final class NovagramCallRecordingsView: NovagramKitView {
    private(set) var host: NSView?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func setHost(_ view: NSView) {
        host?.removeFromSuperview()
        view.frame = bounds
        addSubview(view)
        host = view
    }

    override func layout() {
        super.layout()
        host?.frame = bounds
    }
}

@available(macOS 14.0, *)
final class NovagramCallRecordingsController: GenericViewController<NovagramCallRecordingsView> {
    private static let titleFontSize: CGFloat = 13
    private static let smallFontSize: CGFloat = 12
    private static let dayFormat = "d MMMM yyyy"

    private let storage: CallRecordingStorage
    private let accessedFolder: URL?
    private let appearanceDisposable = MetaDisposable()

    override init() {
        if let folder = NovagramCallRecordingSettings.resolveFolder() {
            self.accessedFolder = folder.startAccessingSecurityScopedResource() ? folder : nil
            self.storage = CallRecordingStorage(directory: folder)
        } else {
            self.accessedFolder = nil
            self.storage = .default
        }
        super.init()
    }

    deinit {
        appearanceDisposable.dispose()
        accessedFolder?.stopAccessingSecurityScopedResource()
    }

    override var enableBack: Bool {
        return true
    }

    override var defaultBarTitle: String {
        return NovagramL10n.current.callRecording_list
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        appearanceDisposable.set(appearanceSignal.start(next: { [weak self] _ in
            self?.updateContent()
        }))
        readyOnce()
    }

    private func updateContent() {
        genericView.backgroundColor = theme.colors.listBackground
        let hosting = NSHostingView(rootView: CallRecordingsListView(storage: storage, environment: makeEnvironment()))
        genericView.setHost(hosting)
    }

    private func makeEnvironment() -> CallRecordingUIEnvironment {
        let colors = theme.colors
        let languageCode = appCurrentLanguage.languageCode
        let recordingTheme = CallRecordingTheme(
            background: Color(nsColor: colors.listBackground),
            card: Color(nsColor: colors.background),
            primaryText: Color(nsColor: colors.text),
            secondaryText: Color(nsColor: colors.grayText),
            accent: Color(nsColor: colors.accent),
            destructive: Color(nsColor: colors.redUI),
            separator: Color(nsColor: colors.border),
            titleFontSize: NovagramCallRecordingsController.titleFontSize,
            subtitleFontSize: NovagramCallRecordingsController.smallFontSize,
            timeFontSize: NovagramCallRecordingsController.smallFontSize,
            freeTextFontSize: NovagramCallRecordingsController.smallFontSize,
            followsDynamicType: false
        )
        var environment = CallRecordingUIEnvironment(
            languageCode: languageCode,
            theme: recordingTheme,
            isRecordingEnabled: NovagramCallRecordingSettings.isEnabled,
            onPlay: { recording in
                NSWorkspace.shared.open(recording.url)
            },
            onShare: { [weak self] urls, rect in
                self?.share(urls, rect: rect)
            }
        )
        let strings = environment.strings
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: languageCode)
        formatter.setLocalizedDateFormatFromTemplate(NovagramCallRecordingsController.dayFormat)
        environment.dayHeader = { day in
            let calendar = Calendar.current
            if calendar.isDateInToday(day) {
                return strings.today
            }
            if calendar.isDateInYesterday(day) {
                return strings.yesterday
            }
            return formatter.string(from: day)
        }
        let sizeFormatter = ByteCountFormatter()
        sizeFormatter.countStyle = .file
        environment.sizeString = { bytes in
            sizeFormatter.string(fromByteCount: bytes)
        }
        return environment
    }

    private func share(_ urls: [URL], rect: CGRect) {
        guard !urls.isEmpty, let host = genericView.host else {
            return
        }
        let anchor = rect == .zero ? NSRect(x: host.bounds.midX, y: host.bounds.midY, width: 1, height: 1) : rect
        let picker = NSSharingServicePicker(items: urls)
        picker.show(relativeTo: anchor, of: host, preferredEdge: .minY)
    }
}

public func makeNovagramCallRecordingsController() -> ViewController? {
    guard #available(macOS 14.0, *) else {
        return nil
    }
    return NovagramCallRecordingsController()
}
