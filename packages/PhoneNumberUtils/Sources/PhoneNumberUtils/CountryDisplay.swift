import Foundation
import TelegramCore

public func emojiFlagForISOCountryCode(_ countryCode: String) -> String {
    
    if countryCode == "FT" {
        return "💎"
    }
    
    if countryCode.count != 2 {
        return ""
    }
    
    if countryCode == "TG" {
        return "🛰️"
    }
   
    
    if countryCode == "XG" {
        return "🛰️"
    } else if countryCode == "XV" {
        return "🌍"
    }
    
    if ["YL"].contains(countryCode) {
        return "🌍"
    }
    
    let base : UInt32 = 127397
    var s = ""
    for v in countryCode.unicodeScalars {
        s.unicodeScalars.append(UnicodeScalar(base + v.value)!)
    }
    return String(s)
}

extension Country {
    public var fullName: String {
        if let code = self.countryCodes.first {
            return "\(emojiFlagForISOCountryCode(self.id))" + " " + name + " +\(code.code)"
        } else {
            return self.name
        }
    }
    public var emojiName: String {
        let emoji = emojiFlagForISOCountryCode(self.id)
        if emoji.isEmpty {
            return self.name
        } else {
            return emojiFlagForISOCountryCode(self.id) + " " + self.name
        }
    }
}
