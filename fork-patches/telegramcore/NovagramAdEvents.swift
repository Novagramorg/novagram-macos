import Foundation

// Novagram Developer switch "Don't send ad events" (pro_messager/novagram_ads_events_off, written by
// NovagramDeveloperFlags.isAdEventsOff): Telegram's sponsored-message views and clicks are not reported
// while it is on, so a developer testing ads does not use up the real impressions. Not tied to Ghost mode.
func novagramAdEventsOff() -> Bool {
    return UserDefaults(suiteName: "pro_messager")?.bool(forKey: "novagram_ads_events_off") == true
}
