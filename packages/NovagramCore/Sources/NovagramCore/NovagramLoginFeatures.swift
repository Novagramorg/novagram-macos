import Foundation

// Login options that differ from Telegram's.
public enum NovagramLoginFeatures {
    // Passkeys need the webcredentials:telegram.org associated domain, which only the official
    // Telegram app can use. Off: no passkey sheet on the login screen, no Passkeys row in Privacy.
    public static let passkeys = false

    // Bot-token login link on the QR and phone screens. Set by the app target at launch
    // (Telegram-Mac/app/main.swift): on in Debug, off in App Store builds.
    public static var botToken = false
}
