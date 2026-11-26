import Foundation

public enum Configuration : String {
    enum Error: Swift.Error {
        case missingKey, invalidValue
    }
    case source = "SOURCE"
    
    public static func value(for key: Configuration) -> String? {
        guard let value = Bundle.main.infoDictionary?[key.rawValue] as? String else {
            return nil
        }
        return value
    }
}
