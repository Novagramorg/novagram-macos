import Cocoa

enum WalletHomeIntro {
    static let balanceDuration: Double = 1.0
    static let minimumBalanceDuration: Double = 0.5
    static let fiatDelay: Double = 0.08
    static let addressScrambleDuration: Double = 0.3
    static let shimmerDelay: Double = 1.3
    static let shimmerDuration: Double = 0.7

    static func make() -> WalletOpenIntro {
        return WalletOpenIntro(rollDuration: balanceDuration, minimumRollDuration: minimumBalanceDuration, duration: shimmerDelay, tail: shimmerDuration)
    }
}
