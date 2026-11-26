import Foundation
import TelegramCore

public extension AppConfiguration {
    func getGeneralValue(_ key: String, orElse defaultValue: Int32) -> Int32 {
        if let value = self.data?[key] as? Double {
            return Int32(value)
        } else {
            return defaultValue
        }
    }
    func getGeneralValue64(_ key: String, orElse defaultValue: Int64) -> Int64 {
        if let value = self.data?[key] as? Double {
            return Int64(value)
        } else {
            return defaultValue
        }
    }
    func getGeneralValueDouble(_ key: String, orElse defaultValue: Double) -> Double {
        if let value = self.data?[key] as? Double {
            return Double(value)
        } else {
            return defaultValue
        }
    }
    func getStringValue(_ key: String, orElse defaultValue: String) -> String {
        if let value = self.data?[key] as? String {
            return value
        } else {
            return defaultValue
        }
    }
    func getBoolValue(_ key: String, orElse defaultValue: Bool) -> Bool {
        if let value = self.data?[key] as? Bool {
            return value
        } else {
            return defaultValue
        }
    }

    /// `rich_message_posting`: 'enabled' | 'premium' | 'disabled'. When 'disabled' the rich text editor UI is
    /// hidden everywhere (attach menu, composer expand button, paste-into-editor).
    var isRichTextEditorEnabled: Bool {
        return getStringValue("rich_message_posting", orElse: "enabled") != "disabled"
    }
}
