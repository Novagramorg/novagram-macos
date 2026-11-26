import Foundation

public func localizedPsa(_ key: String, type: String, args: [CVarArg] = []) -> String {
    let fullKey = key + "." + type
    let cloud = translate(key: fullKey, args)
    if cloud == fullKey {
        return translate(key: key, args)
    } else {
        return cloud
    }
}
