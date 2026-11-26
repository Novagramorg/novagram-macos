import Foundation

public struct CreateGroupRequires : OptionSet {
    public var rawValue: Int32
    
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }
    
    public static let username = CreateGroupRequires(rawValue: 1 << 1)
    public static let forum = CreateGroupRequires(rawValue: 1 << 2)
}
