import AppKit
import AVFoundation
import TGUIKit
import SwiftSignalKit
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramMediaUtils

public struct NovagramCallDeviceMenuStrings {
    public let microphone: String
    public let speaker: String
    public let systemDefault: String

    public init(microphone: String, speaker: String, systemDefault: String) {
        self.microphone = microphone
        self.speaker = speaker
        self.systemDefault = systemDefault
    }
}

public func novagramPresentCallDeviceMenu(sharedContext: any SharedAccountContextProtocol, view: NSView, event: NSEvent, strings: NovagramCallDeviceMenuStrings) {
    let accountManager = sharedContext.accountManager
    let devices = CallSettingsHooks.shared.devicesContext(sharedContext).signal |> filter { !$0.loading } |> take(1)
    let signal = combineLatest(voiceCallSettings(accountManager) |> take(1), devices) |> deliverOnMainQueue
    _ = signal.start(next: { [weak view] settings, devices in
        guard let view else {
            return
        }
        let menu = ContextMenu(presentation: .current(TelegramThemeHooks.shared.darkAppearance().colors))
        let selectInput: (String?) -> Void = { id in
            _ = updateVoiceCallSettingsSettingsInteractively(accountManager: accountManager, { $0.withUpdatedAudioInputDeviceId(id) }).start()
        }
        let selectOutput: (String?) -> Void = { id in
            _ = updateVoiceCallSettingsSettingsInteractively(accountManager: accountManager, { $0.withUpdatedAudioOutputDeviceId(id) }).start()
        }
        let inputs = devices.audioInput.map { (id: $0.uniqueID, name: $0.localizedName) }
        let outputs = devices.audioOutput.map { (id: $0.uniqueID, name: $0.localizedName) }
        menu.addItem(novagramDeviceSection(title: strings.microphone, systemDefault: strings.systemDefault, devices: inputs, current: settings.audioInputDeviceId, select: selectInput))
        menu.addItem(novagramDeviceSection(title: strings.speaker, systemDefault: strings.systemDefault, devices: outputs, current: settings.audioOutputDeviceId, select: selectOutput))
        AppMenu.show(menu: menu, event: event, for: view)
    })
}

private func novagramDeviceSection(title: String, systemDefault: String, devices: [(id: String, name: String)], current: String?, select: @escaping (String?) -> Void) -> ContextMenuItem {
    let currentName = devices.first(where: { $0.id == current })?.name ?? systemDefault
    let item = ContextMenuItem("\(title): \(currentName)")
    let submenu = ContextMenu(presentation: .current(TelegramThemeHooks.shared.darkAppearance().colors))
    submenu.addItem(ContextMenuItem(systemDefault, handler: {
        select(nil)
    }, state: current == nil ? .on : nil))
    for device in devices {
        submenu.addItem(ContextMenuItem(device.name, handler: {
            select(device.id)
        }, state: current == device.id ? .on : nil))
    }
    item.submenu = submenu
    return item
}
