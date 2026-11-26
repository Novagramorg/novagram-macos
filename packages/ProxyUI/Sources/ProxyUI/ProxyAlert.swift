import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import MtProtoKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import GeneralRows
import InputDataUI
import AlertsUI
import ProxyUtils

private func makeProxyAlertData(server: ProxyServerSettings, context: (any AccountContextProtocol), status: ProxyServerStatus?, checkStatus: @escaping () -> Void) -> ModalAlertData {
    var rows: [InputDataTableBasedItem.Row] = []

    rows.append(.init(
        left: .init(.initialize(string: strings().proxyServer, color: theme.colors.grayText, font: .normal(.text))),
        right: .init(name: .init(.initialize(string: server.webProxyAddress ?? server.host, color: theme.colors.text, font: .normal(.text))))
    ))

    if server.webProxyAddress == nil {
        rows.append(.init(
            left: .init(.initialize(string: strings().proxyPort, color: theme.colors.grayText, font: .normal(.text))),
            right: .init(name: .init(.initialize(string: "\(server.port)", color: theme.colors.text, font: .normal(.text))))
        ))
    }

    switch server.connection {
    case let .socks5(username, password):
        if let username = username, !username.isEmpty {
            rows.append(.init(
                left: .init(.initialize(string: strings().proxyUsername, color: theme.colors.grayText, font: .normal(.text))),
                right: .init(name: .init(.initialize(string: username, color: theme.colors.text, font: .normal(.text))))
            ))
        }
        if let password = password, !password.isEmpty {
            rows.append(.init(
                left: .init(.initialize(string: strings().proxyPassword, color: theme.colors.grayText, font: .normal(.text))),
                right: .init(name: .init(.initialize(string: password, color: theme.colors.text, font: .normal(.text))))
            ))
        }
    case let .mtp(secret):
        let secretString = MTProxySecret.parseData(secret)?.serializeToString() ?? ""
        rows.append(.init(
            left: .init(.initialize(string: strings().proxySettingsSecret, color: theme.colors.grayText, font: .normal(.text))),
            right: .init(name: .init(.initialize(string: secretString, color: theme.colors.text, font: .normal(.text))))
        ))
    case .web:
        break
    }

    let statusLayout: TextViewLayout
    if case .web = server.connection {
        statusLayout = TextViewLayout(.initialize(string: strings().proxySettingsWebNotTested, color: theme.colors.grayText, font: .normal(.text)))
    } else if let status = status {
        let statusText: String
        let statusColor: NSColor
        switch status {
        case .checking:
            statusText = strings().proxySettingsItemChecking + "..."
            statusColor = theme.colors.grayText
        case .notAvailable:
            statusText = strings().proxySettingsItemNeverConnected
            statusColor = theme.colors.redUI
        case let .available(ping):
            statusText = "\("\(Int(ping * 1000)) ms ping")"
            statusColor = theme.colors.text
        }
        statusLayout = TextViewLayout(.initialize(string: statusText, color: statusColor, font: .normal(.text)))
    } else {
        let attr = NSMutableAttributedString()
        _ = attr.append(string: strings().proxyCheckStatus, color: theme.colors.accent, font: .normal(.text))
        attr.addAttribute(.link, value: "check://status", range: attr.range)
        statusLayout = TextViewLayout(attr)
        statusLayout.interactions.processURL = { _ in
            checkStatus()
        }
    }

    rows.append(.init(
        left: .init(.initialize(string: strings().proxyStatus, color: theme.colors.grayText, font: .normal(.text))),
        right: .init(name: statusLayout)
    ))

    var info = strings().proxyForceEnableText
    if case .mtp = server.connection {
        info += "\n\n" + strings().proxyForceEnableMTPDesc
    } else if case .web = server.connection {
        info += "\n\n" + strings().proxySettingsWebWarningText
    }

    let statusId: String
    if let status = status {
        switch status {
        case .checking:
            statusId = "checking"
        case .notAvailable:
            statusId = "notAvailable"
        case let .available(ping):
            statusId = "available_\(ping)"
        }
    } else {
        statusId = "none"
    }

    return ModalAlertData(
        title: strings().proxySettingsTitle,
        info: info,
        ok: strings().proxyForceEnableConnect,
        options: [],
        mode: .alert,
        footer: .init(id: AnyHashable(statusId), value: { initialSize, stableId, presentation, _ in
            return InputDataTableBasedItem(initialSize, stableId: stableId, viewType: .singleItem, rows: rows, context: context)
        })
    )
}

private func checkProxyStatus(context: (any AccountContextProtocol), server: ProxyServerSettings) -> Signal<ProxyServerStatus, NoError> {
    let settings: MTSocksProxySettings
    switch server.connection {
    case let .socks5(username, password):
        settings = MTSocksProxySettings(ip: server.host, port: UInt16(clamping: server.port), username: username, password: password, secret: nil)
    case let .mtp(secret):
        settings = MTSocksProxySettings(ip: server.host, port: UInt16(clamping: server.port), username: nil, password: nil, secret: secret)
    case .web:
        return .single(.notAvailable)
    }

    return Signal { subscriber in
        subscriber.putNext(.checking)
        let disposable = MTProxyConnectivity.pingProxy(with: context.account.network.context, datacenterId: context.account.network.datacenterId, settings: settings).start(next: { result in
            if let result = result as? MTProxyConnectivityStatus {
                subscriber.putNext(result.reachable ? .available(result.roundTripTime) : .notAvailable)
            }
        })
        return ActionDisposable {
            disposable?.dispose()
        }
    }
}

public func applyExternalProxy(_ server: ProxyServerSettings, accountManager: AccountManager<TelegramAccountManagerTypes>) {
    guard let context = ProxyHooks.shared.currentContext() else {
        return
    }

    let statusDisposable = MetaDisposable()
    var proxyStatus: ProxyServerStatus? = nil
    var updateData: ((ModalAlertData) -> Void)? = nil

    var checkStatus: (() -> Void)!
    checkStatus = {
        let header: String
        let information: String
        let ok: String
        if case .web = server.connection {
            header = strings().proxySettingsWebWarningTitle
            information = strings().proxySettingsWebWarningText
            ok = strings().proxySettingsWebWarningEnable
        } else {
            header = strings().proxyWarning
            information = strings().proxyWarningInfo
            ok = strings().proxyProceed
        }
        verifyAlert_button(for: context.window, header: header, information: information, ok: ok, successHandler: { _ in
            if case .web = server.connection {
                return
            }
            statusDisposable.set((checkProxyStatus(context: context, server: server)
                |> deliverOnMainQueue).start(next: { status in
                    proxyStatus = status
                    updateData?(makeProxyAlertData(server: server, context: context, status: proxyStatus, checkStatus: checkStatus))
                }))
        })
    }

    let initialData = makeProxyAlertData(server: server, context: context, status: nil, checkStatus: checkStatus)

    showModalAlert(for: context.window, data: initialData, completion: { _ in
        statusDisposable.dispose()
        _ = updateProxySettingsInteractively(accountManager: accountManager, { current -> ProxySettings in
            return current.withAddedServer(server).withUpdatedActiveServer(server).withUpdatedEnabled(true)
        }).start()
    }, cancel: {
        statusDisposable.dispose()
    }, onDeinit: {
        statusDisposable.dispose()
        checkStatus = nil
        updateData = nil
    }, takeNewData: { update in
        updateData = update
    })
}
