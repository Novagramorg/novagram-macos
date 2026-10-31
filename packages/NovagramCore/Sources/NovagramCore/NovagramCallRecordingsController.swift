import Cocoa
import SwiftUI
import TGUIKit
import SwiftSignalKit
import TelegramTheme
import Localization
import AlertsUI
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
    private lazy var model: CallRecordingsListViewModel = MainActor.assumeIsolated { CallRecordingsListViewModel(storage: storage) }
    private var strings: CallRecordingStrings {
        return CallRecordingStrings(languageCode: appCurrentLanguage.languageCode)
    }
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
        return strings.title
    }

    override func getRightBarViewOnce() -> BarView {
        let bar = ImageBarView(controller: self, theme.icons.chatActions)
        bar.button.contextMenu = { [weak self] in
            return self?.makeMenu()
        }
        return bar
    }

    private func makeMenu() -> NovagramMenu {
        let strings = self.strings
        let model = self.model
        let menu = NovagramMenu()
        let current = MainActor.assumeIsolated { model.filter }
        for filter in CallRecordingFilter.allCases {
            let item = ContextMenuItem(filter.title(strings), handler: {
                MainActor.assumeIsolated {
                    model.filter = filter
                }
            })
            item.state = filter == current ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(ContextSeparatorItem())
        let selected = MainActor.assumeIsolated { model.selectedURLs }
        let allSelected = MainActor.assumeIsolated { model.allVisibleSelected }
        let isSelecting = MainActor.assumeIsolated { model.isSelecting }
        if isSelecting || !selected.isEmpty {
            menu.addItem(ContextMenuItem(allSelected ? strings.deselectAll : strings.selectAll, handler: {
                MainActor.assumeIsolated {
                    model.toggleSelectAll()
                }
            }))
            if !selected.isEmpty {
                menu.addItem(ContextMenuItem(strings.share, handler: { [weak self] in
                    self?.share(selected, rect: .zero)
                }))
                menu.addItem(ContextMenuItem(strings.deleteSelectedButton(selected.count), handler: { [weak self] in
                    self?.confirmDelete(selected)
                }, itemMode: .destruct))
            }
            menu.addItem(ContextMenuItem(strings.done, handler: {
                MainActor.assumeIsolated {
                    model.setSelecting(false)
                }
            }))
        } else {
            menu.addItem(ContextMenuItem(strings.select, handler: {
                MainActor.assumeIsolated {
                    model.setSelecting(true)
                }
            }))
        }
        let hasRecordings = !MainActor.assumeIsolated { model.visibleRecordings.isEmpty }
        if hasRecordings {
            menu.addItem(ContextSeparatorItem())
            menu.addItem(ContextMenuItem(strings.clearAll, handler: {
                MainActor.assumeIsolated {
                    model.requestClearAll()
                }
            }, itemMode: .destruct))
        }
        return menu
    }

    private func confirmDelete(_ urls: [URL]) {
        guard let window = self.window else {
            return
        }
        let strings = self.strings
        let model = self.model
        verifyAlert(for: window, information: strings.deleteSelectedConfirm(urls.count), ok: strings.delete, cancel: strings.cancel, successHandler: { _ in
            MainActor.assumeIsolated {
                _ = model.delete(urls)
                model.setSelecting(false)
            }
        })
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
        let model = self.model
        let environment = makeEnvironment()
        let hosting = MainActor.assumeIsolated { NSHostingView(rootView: CallRecordingsListView(model: model, environment: environment)) }
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
            followsDynamicType: false,
            freeText: Color(nsColor: colors.grayText)
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
        environment.showsToolbar = false
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
        let anchor: NSRect
        if rect == .zero {
            anchor = NSRect(x: host.bounds.midX, y: host.bounds.midY, width: 1, height: 1)
        } else if let contentView = host.window?.contentView {
            anchor = host.convert(NSRect(x: rect.minX, y: contentView.bounds.height - rect.maxY, width: rect.width, height: rect.height), from: nil)
        } else {
            anchor = rect
        }
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
