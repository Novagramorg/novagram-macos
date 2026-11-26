import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import InAppSettings
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif

public struct VoipDerivedState: Equatable, Codable {
    public var data: Data
    
    public static var `default`: VoipDerivedState {
        return VoipDerivedState(data: Data())
    }
    
    public init(data: Data) {
        self.data = data
    }
    
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        self.data = try container.decode(Data.self, forKey: "data")
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(self.data, forKey: "data")
    }
    
}

public func updateVoipDerivedStateInteractively(postbox: Postbox, _ f: @escaping (VoipDerivedState) -> VoipDerivedState) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        transaction.updatePreferencesEntry(key: ApplicationSpecificPreferencesKeys.voipDerivedState, { entry in
            let currentSettings: VoipDerivedState
            if let entry = entry?.get(VoipDerivedState.self) {
                currentSettings = entry
            } else {
                currentSettings = .default
            }
            return PreferencesEntry(f(currentSettings))
        })
    }
}
