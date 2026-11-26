import Foundation

public final class Account { public init() {} }
public final class InlineStickersContext { public init() {} }
public enum LiteMode { case emoji }
public protocol AccountContextProtocol: AnyObject {
    var account: Account { get }
    var inlinePacksContext: InlineStickersContext { get }
    func isLite(_ mode: LiteMode) -> Bool
}
public final class TestContext: AccountContextProtocol {
    public var account: Account
    public let inlinePacksContext = InlineStickersContext()
    public var lite = false
    public init(account: Account = Account()) { self.account = account }
    public func isLite(_ mode: LiteMode) -> Bool { lite }
}
