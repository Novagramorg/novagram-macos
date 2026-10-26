//
//  NovagramHiddenChatsManager.swift
//  Telegram-Mac
//
//  iOS parity: submodules/Novagram/SecretVault
//  Features #31 & #32: Yashirin chatlar (Hidden Chats / Secret Vault)
//  Allows users to hide sensitive chats from the chat list, protected
//  by Touch ID / Master PIN / biometric authentication.
//

import Foundation
import Cocoa
import Postbox
import TelegramCore
import LocalAuthentication
import TGUIKit

private let kHiddenChatsSuite = "pro_messager"
private let kHiddenPeerIdsKey = "hidden_chat_peer_ids"

public final class NovagramHiddenChatsManager {
    public static let shared = NovagramHiddenChatsManager()

    private let defaults = UserDefaults(suiteName: kHiddenChatsSuite)
    // Read from the chat list preparation queue, written on the main thread.
    private let lockObject = NSLock()
    private var _hiddenIds: Set<Int64> = []
    private var hiddenIds: Set<Int64> {
        get { lockObject.lock(); defer { lockObject.unlock() }; return _hiddenIds }
        set { lockObject.lock(); _hiddenIds = newValue; lockObject.unlock() }
    }
    
    /// Runtime state: whether hidden chats are currently revealed (unlocked) in this session
    private(set) var isRevealed: Bool = false

    private init() {
        if let stored = defaults?.array(forKey: kHiddenPeerIdsKey) as? [Int64] {
            hiddenIds = Set(stored)
        } else if let storedStrings = defaults?.array(forKey: kHiddenPeerIdsKey) as? [String] {
            hiddenIds = Set(storedStrings.compactMap { Int64($0) })
        }
    }

    // MARK: - Query

    public func isHidden(peerId: PeerId) -> Bool {
        if isRevealed {
            return false
        }
        return hiddenIds.contains(peerId.toInt64())
    }

    public func isPeerHiddenInStorage(_ peerId: PeerId) -> Bool {
        return hiddenIds.contains(peerId.toInt64())
    }

    public var hiddenCount: Int {
        return hiddenIds.count
    }

    // MARK: - Mutation

    public func setHidden(_ hidden: Bool, for peerId: PeerId) {
        let rawId = peerId.toInt64()
        if hidden {
            hiddenIds.insert(rawId)
        } else {
            hiddenIds.remove(rawId)
        }
        save()
        NotificationCenter.default.post(name: NSNotification.Name("NovagramSettingsChanged"), object: nil)
    }

    public func toggleHidden(for peerId: PeerId) {
        setHidden(!isPeerHiddenInStorage(peerId), for: peerId)
    }

    private func save() {
        defaults?.set(Array(hiddenIds), forKey: kHiddenPeerIdsKey)
    }

    // MARK: - Reveal / Lock

    public func lock() {
        isRevealed = false
        NotificationCenter.default.post(name: NSNotification.Name("NovagramSettingsChanged"), object: nil)
    }

    public func unlockDirectly() {
        isRevealed = true
        NotificationCenter.default.post(name: NSNotification.Name("NovagramSettingsChanged"), object: nil)
    }

    public func toggleReveal(for window: Window?, completion: ((Bool) -> Void)? = nil) {
        if isRevealed {
            lock()
            completion?(false)
            return
        }

        // Authentication needed to unlock
        let laContext = LAContext()
        var error: NSError?
        
        let authenticateWithPin: () -> Void = { [weak self] in
            guard let self = self else { return }
            if NovagramChatPincodeManager.shared.isMasterEnabled() {
                if let window = window {
                    NovagramChatPincode.presentVerify(for: window, verify: { code in
                        return NovagramChatPincodeManager.shared.verifyMaster(code)
                    }, onSuccess: {
                        self.unlockDirectly()
                        completion?(true)
                    })
                } else {
                    self.unlockDirectly()
                    completion?(true)
                }
            } else {
                // If no master PIN set, reveal directly
                self.unlockDirectly()
                completion?(true)
            }
        }

        if laContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            laContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Yashirin chatlarni ko'rsatish uchun Touch ID tasdiqlang") { success, _ in
                DispatchQueue.main.async {
                    if success {
                        self.unlockDirectly()
                        completion?(true)
                    } else {
                        authenticateWithPin()
                    }
                }
            }
        } else {
            authenticateWithPin()
        }
    }
}
