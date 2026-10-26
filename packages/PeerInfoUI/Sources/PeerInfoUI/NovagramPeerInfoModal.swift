import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramTheme
import AlertsUI
import NovagramCore

// "Novagram Info" modal, opened from the info button in the peer info header (old fork: PeerInfoController.swift).
func NovagramInfoModalController(context: any AccountContextProtocol, peerView: PeerView) -> InputDataModalController {
    let l10n = NovagramL10n.current
    let peer = peerViewMainPeer(peerView)
    let peerId = peerView.peerId

    let formattedId: String
    if peerId.namespace == Namespaces.Peer.CloudChannel {
        formattedId = "-100\(peerId.id._internalGetInt64Value())"
    } else if peerId.namespace == Namespaces.Peer.CloudGroup {
        formattedId = "-\(peerId.id._internalGetInt64Value())"
    } else {
        formattedId = "\(peerId.id._internalGetInt64Value())"
    }

    let peerTypeString: String
    if let user = peer as? TelegramUser {
        peerTypeString = user.botInfo != nil ? l10n.info_typeBot : l10n.info_typeUser
    } else if let channel = peer as? TelegramChannel {
        if case .group = channel.info {
            peerTypeString = l10n.info_typeSupergroup
        } else {
            peerTypeString = l10n.info_typeChannel
        }
    } else if peer is TelegramGroup {
        peerTypeString = l10n.info_typeGroup
    } else if peer is TelegramSecretChat {
        peerTypeString = l10n.info_typeSecretChat
    } else {
        peerTypeString = l10n.info_unknown
    }

    var dcString: String = l10n.info_unknown
    if let photo = peer?.profileImageRepresentations.first?.resource as? CloudPeerPhotoSizeMediaResource {
        dcString = "DC \(photo.datacenterId)"
    } else if let cachedChannelData = peerView.cachedData as? CachedChannelData, cachedChannelData.statsDatacenterId != 0 {
        dcString = "DC \(cachedChannelData.statsDatacenterId)"
    }

    let username: String?
    if let user = peer as? TelegramUser {
        username = user.addressName ?? user.usernames.first(where: { $0.isActive })?.username
    } else {
        username = peer?.addressName
    }
    let usernameString = username.map { "@\($0)" } ?? l10n.info_none

    let scamFakeString: String
    if peer?.isScam == true {
        scamFakeString = l10n.info_scam
    } else if peer?.isFake == true {
        scamFakeString = l10n.info_fake
    } else {
        scamFakeString = l10n.info_clean
    }

    let premiumString = peer?.isPremium == true ? l10n.info_yes : l10n.info_no

    let copy: (String, String) -> Void = { value, toast in
        copyToClipboard(value)
        showModalText(for: context.window, text: toast)
    }

    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    func row(_ id: String, _ name: String, _ value: String, _ viewType: GeneralViewType, action: (() -> Void)? = nil) {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init(id), data: InputDataGeneralData(name: name, color: theme.colors.text, type: .context(value), viewType: viewType, enabled: true, action: action)))
        index += 1
    }

    row("peer_id", l10n.peerInfo_idLabel, formattedId, .firstItem, action: {
        copy(formattedId, l10n.peerInfo_idCopied)
    })
    row("peer_type", l10n.info_type, peerTypeString, .innerItem)
    row("dc_id", l10n.info_dataCenter, dcString, .innerItem)
    row("username", l10n.info_username, usernameString, .innerItem, action: username == nil ? nil : {
        copy(usernameString, strings().shareLinkCopied)
    })
    row("scam_fake", l10n.info_status, scamFakeString, .innerItem)
    row("premium", l10n.info_premium, premiumString, .lastItem)

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    let controller = InputDataController(dataSignal: .single(InputDataSignalValue(entries: entries)), title: l10n.info_title)
    var close: (() -> Void)? = nil
    let modalInteractions = ModalInteractions(acceptTitle: strings().modalOK, accept: {
        close?()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    return modalController
}

private let novagramInfoButtonId = NSUserInterfaceItemIdentifier("fenixuz.peerInfo.info")

private func novagramInfoIcon(_ color: NSColor) -> CGImage? {
    let image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Novagram Info")
    return image?.precomposed(color)
}

// Info button in the right part of the peer info header; opens NovagramInfoModalController.
func novagramAddInfoButton(to bar: BarView, handler: @escaping () -> Void) {
    let button = ImageButton()
    button.identifier = novagramInfoButtonId
    button.autohighlight = false
    button.scaleOnClick = true
    if let icon = novagramInfoIcon(theme.colors.accent) {
        button.set(image: icon, for: .Normal)
    }
    button.frame = NSMakeRect(5, 10, 30, 30)
    button.set(handler: { _ in
        handler()
    }, for: .Click)
    button.toolTip = NovagramL10n.current.info_title
    bar.addSubview(button)
}

func novagramUpdateInfoButton(in bar: BarView?, color: NSColor) {
    guard let button = bar?.subviews.first(where: { $0.identifier == novagramInfoButtonId }) as? ImageButton else {
        return
    }
    if let icon = novagramInfoIcon(color) {
        button.set(image: icon, for: .Normal)
    }
}
