import Foundation

public struct CreateChannelRequires : OptionSet {
    public var rawValue: Int32
    
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }
    public static let username = CreateChannelRequires(rawValue: 1 << 1)
}
