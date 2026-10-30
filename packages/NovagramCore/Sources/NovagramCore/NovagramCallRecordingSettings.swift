import AppKit
import TGUIKit
import AlertsUI
import NovagramCallRecordingCore

// Mac-only local call recording settings (pro_messager suite). The folder is an app-scoped security-scoped bookmark.
public enum NovagramCallRecordingSettings {
    public static let enabledKey = CallRecordingSettings.enabledKey
    public static let folderKey = "novagram_call_recording_folder"
    public static let autoKey = CallRecordingSettings.autoKey
    public static let dataSavingKey = "novagram_call_data_saving"
    static let captureRequestedKey = "novagram_call_recording_capture_requested"

    private static var defaults: UserDefaults? {
        return UserDefaults(suiteName: "pro_messager")
    }

    private static var shared: CallRecordingSettings {
        return CallRecordingSettings()
    }

    public static var isSupported: Bool {
        if #available(macOS 14.0, *) {
            return true
        }
        return false
    }

    public static var isEnabled: Bool {
        return isSupported && NovagramDeveloperFlags.isCallRecordingEnabled && isStoredEnabled
    }

    public static var isStoredEnabled: Bool {
        return shared.isUserEnabled
    }

    public static func setEnabled(_ value: Bool) {
        shared.isUserEnabled = value
    }

    public static var isAutoStored: Bool {
        return shared.isUserAutoEnabled
    }

    public static var isAutoEnabled: Bool {
        return isEnabled && isAutoStored
    }

    public static func setAutoEnabled(_ value: Bool) {
        shared.isUserAutoEnabled = value
    }

    public static var isDataSavingEnabled: Bool {
        return defaults?.bool(forKey: dataSavingKey) ?? false
    }

    static var wasWarned: Bool {
        get {
            return shared.wasWarned
        }
        set {
            shared.wasWarned = newValue
        }
    }

    static var didRequestCapture: Bool {
        get {
            return defaults?.bool(forKey: captureRequestedKey) ?? false
        }
        set {
            defaults?.set(newValue, forKey: captureRequestedKey)
        }
    }

    public static func clearFolder() {
        defaults?.removeObject(forKey: folderKey)
    }

    @discardableResult
    static func storeFolder(_ url: URL) -> Bool {
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return false
        }
        defaults?.set(data, forKey: folderKey)
        return true
    }

    static func resolveFolder() -> URL? {
        guard let data = defaults?.data(forKey: folderKey) else {
            return nil
        }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
            return nil
        }
        if isStale {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard storeFolder(url) else {
                return nil
            }
        }
        return url
    }

    public static var folderDisplayPath: String? {
        guard let path = resolveFolder()?.path else {
            return nil
        }
        let home = realHomeDirectory
        if path == home || path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private static var realHomeDirectory: String {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    public static func chooseFolder(window: NSWindow?, completion: @escaping (Bool) -> Void) {
        let l10n = NovagramL10n.current
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = l10n.callRecording_choose
        panel.message = l10n.callRecording_chooseMessage
        if let current = resolveFolder() {
            panel.directoryURL = current
        }
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else {
                completion(false)
                return
            }
            completion(storeFolder(url))
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: handler)
        } else {
            panel.begin(completionHandler: handler)
        }
    }

    public static func changeFolder(window: Window, completion: @escaping () -> Void) {
        guard let path = folderDisplayPath else {
            chooseFolder(window: window, completion: { _ in completion() })
            return
        }
        let l10n = NovagramL10n.current
        verifyAlert_button(for: window, header: l10n.callRecording_saveTo, information: path, ok: l10n.callRecording_chooseFolder, cancel: l10n.callRecording_cancel, option: l10n.callRecording_askEveryTime, successHandler: { result in
            switch result {
            case .basic:
                chooseFolder(window: window, completion: { _ in completion() })
            case .thrid:
                clearFolder()
                completion()
            }
        })
    }
}
