import Foundation
import TelegramCore
import Postbox
import SwiftSignalKit
import MtProtoKit
import FoundationUtils

public func proxySettings(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<ProxySettings, NoError>  {
    return accountManager.sharedData(keys: [SharedDataKeys.proxySettings]) |> map { view in
        return view.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
    }
}

public extension ProxySettings {
    func withUpdatedActiveServer(_ activeServer: ProxyServerSettings?) -> ProxySettings {
        return ProxySettings(enabled: self.enabled, servers: servers, activeServer: activeServer, useForCalls: self.useForCalls)
    }
    
    func withUpdatedEnabled(_ enabled: Bool) -> ProxySettings {
        return ProxySettings(enabled: enabled, servers: self.servers, activeServer: self.activeServer, useForCalls: self.useForCalls)
    }
    
    func withAddedServer(_ proxy: ProxyServerSettings) -> ProxySettings {
        var servers = self.servers
        if servers.first(where: {$0 == proxy}) == nil {
            servers.append(proxy)
        }
        return ProxySettings(enabled: self.enabled, servers: servers, activeServer: self.activeServer, useForCalls: self.useForCalls)
    }
    
    func withUpdatedServer(_ current: ProxyServerSettings, with updated: ProxyServerSettings) -> ProxySettings {
        var servers = self.servers
        if let index = servers.firstIndex(where: {$0 == current}) {
            servers[index] = updated
        } else {
            servers.append(updated)
        }
        var activeServer = self.activeServer
        if activeServer == current {
            activeServer = updated
        }
        return ProxySettings(enabled: self.enabled, servers: servers, activeServer: activeServer, useForCalls: self.useForCalls)
    }
    
    func withUpdatedUseForCalls(_ enable: Bool) -> ProxySettings {
        return ProxySettings(enabled: self.enabled, servers: servers, activeServer: self.activeServer, useForCalls: enable)
    }
    
    func withRemovedServer(_ proxy: ProxyServerSettings) -> ProxySettings {
        var servers = self.servers
        var activeServer = self.activeServer
        var enabled: Bool = self.enabled
        if let index = servers.firstIndex(where: {$0 == proxy}) {
            _ = servers.remove(at: index)
        }
        if proxy == activeServer {
            activeServer = nil
            enabled = false
        }
        return ProxySettings(enabled: enabled, servers: servers, activeServer: activeServer, useForCalls: self.useForCalls)
    }
}

public extension ProxyServerSettings {
    var link: String {
        let prefix: String
        switch self.connection {
        case .mtp:
            prefix = "proxy"
        case .socks5:
            prefix = "socks"
        case .web:
            prefix = "webproxy"
        }
        var link: String
        if case .web = self.connection {
            return webProxySettingsLink(self) ?? ""
        } else {
            link = "tg://\(prefix)?server=\(self.host)&port=\(self.port)"
        }
        switch self.connection {
        case let .mtp(secret):
            link += "&secret=\((secret as NSData).hexString)"
        case let .socks5(username, password):
            if let username = username {
                link += "&user=\(username)"
            }
            if let password = password {
                link += "&pass=\(password)"
            }
        case .web:
            break
        }
        return link
    }
    
    var isEmpty: Bool {
        if host.isEmpty {
            return true
        }
        if port == 0 {
            return true
        }
        switch self.connection {
        case let .mtp(secret):
            if secret.isEmpty {
                return true
            }
        case let .web(secret, path):
            let address = path.isEmpty ? host : "\(host)/\(path)"
            if parseWebProxySecret(webProxySecretString(secret)) == nil || canonicalWebProxyAddress(address) == nil {
                return true
            }
        default:
            break
        }
        return false
    }
}
