import Foundation
import InAppSettings

private let novagramCallDataSavingKey = "novagram_call_data_saving"
private let novagramCallDataSavingFlagKey = "novagram_dev_call_data_saving"

func novagramCallDataSaving() -> VoiceCallDataSaving {
    let defaults = UserDefaults(suiteName: "pro_messager")
    let isAvailable = defaults?.bool(forKey: novagramCallDataSavingFlagKey) ?? false
    let isEnabled = defaults?.bool(forKey: novagramCallDataSavingKey) ?? false
    return isAvailable && isEnabled ? .always : .never
}
