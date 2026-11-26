import Foundation

__SETTINGS__

enum Flag: Hashable { case translationHidden }
class CachedChannelData { var flags: Set<Flag> = [] }
class CachedGroupData { var flags: Set<Flag> = [] }
class CachedUserData { var flags: Set<Flag> = [] }
struct Peer { var isPremium: Bool }
struct Settings { var paywall: TranslatePaywall? }
struct TranslationState { var paywall = false }

func visibility(_ cachedData: Any?, premium: Bool, paywall: TranslatePaywall?) -> (hidden: Bool, paywall: Bool?) {
    let peer: Peer? = Peer(isPremium: premium)
    let settings = Settings(paywall: paywall)
    let translationState: TranslationState? = TranslationState()
    do {
        __VISIBILITY__
        return (isHidden, translationState?.paywall)
    }
}

var failures = 0
func check(_ passed: Bool, _ name: String) {
    print("\(passed ? "PASS" : "FAIL"): \(name)")
    if !passed { failures += 1 }
}

let now = Int32(Date().timeIntervalSince1970)
let eligible = TranslatePaywall(timestamp: now - 60, count: 3)
let dismissed = eligible.flush()
let expired = TranslatePaywall(timestamp: now - 1, count: dismissed.count + 2)

for cachedData: Any in [CachedChannelData(), CachedGroupData(), CachedUserData()] {
    let kind = String(describing: type(of: cachedData))
    let before = visibility(cachedData, premium: false, paywall: eligible)
    check(!before.hidden && before.paywall == true, "\(kind): eligible non-Premium prompt appears")
    check(visibility(cachedData, premium: false, paywall: nil).hidden == false, "\(kind): initial prompt remains available")
    check(visibility(cachedData, premium: false, paywall: dismissed).hidden, "\(kind): Hide translation dismisses prompt")
    check(visibility(cachedData, premium: false, paywall: dismissed).hidden, "\(kind): reopening respects dismissal")
    let increased = dismissed.increase().increase().increase()
    check(visibility(cachedData, premium: false, paywall: increased).hidden, "\(kind): activity cannot bypass cooldown")
    check(!visibility(cachedData, premium: false, paywall: expired).hidden, "\(kind): eligible prompt returns after cooldown")
    let premium = visibility(cachedData, premium: true, paywall: dismissed)
    check(!premium.hidden && premium.paywall == false, "\(kind): Premium translation remains available")
}

let hiddenChannel = CachedChannelData()
hiddenChannel.flags.insert(.translationHidden)
check(visibility(hiddenChannel, premium: false, paywall: eligible).hidden, "chat translation hidden flag remains respected")
check(visibility(nil, premium: false, paywall: eligible).hidden, "missing chat data stays hidden")
check(dismissed.timestamp >= now + 7 * 24 * 60 * 60, "dismissal retains seven-day cooldown")
if failures > 0 { exit(1) }
