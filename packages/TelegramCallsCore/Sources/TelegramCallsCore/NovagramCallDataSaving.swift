import Foundation
import InAppSettings

private let novagramCallDataSavingKey = "novagram_call_data_saving"

func novagramCallDataSaving() -> VoiceCallDataSaving {
    let isEnabled = UserDefaults(suiteName: "pro_messager")?.bool(forKey: novagramCallDataSavingKey) ?? false
    return isEnabled ? .always : .never
}
