import Foundation
import LocalAuthentication

public extension LAPolicy {
    static var applicationPolicy: LAPolicy {
        if #available(macOS 10.15, *) {
            return .deviceOwnerAuthenticationWithBiometricsOrWatch
        } else {
            return .deviceOwnerAuthentication
        }
    }
}

public extension LAContext {
    var canUseBiometric: Bool {
        return true
    }
    
    var biometricTypeString: String {
        let type: String
        if #available(macOS 10.13.2, *) {
            switch self.biometryType {
            case .faceID:
                type = "face"
            case .touchID:
                type = "finger"
            case .opticID:
                type = "unknown"
            case .none:
                type = "unknown"
            @unknown default:
                type = "unknown"
            }
        } else {
           type = "finger"
        }
        return type
    }
}
