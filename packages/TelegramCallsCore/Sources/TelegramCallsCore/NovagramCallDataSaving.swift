import Foundation
import InAppSettings

private let novagramCallDataSavingKey = "novagram_call_data_saving"

func novagramCallDataSaving() -> VoiceCallDataSaving {
    let defaults = UserDefaults(suiteName: "pro_messager")
    let isEnabled = defaults?.bool(forKey: novagramCallDataSavingKey) ?? false
    return isEnabled ? .always : .never
}
