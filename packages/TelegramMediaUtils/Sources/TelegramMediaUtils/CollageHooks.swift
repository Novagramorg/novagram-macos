import Foundation
import TelegramCore

public struct CollageHooks {
    public let fileAttributes: (String, String, Bool, Bool) -> [TelegramMediaFileAttribute]

    public init(fileAttributes: @escaping (String, String, Bool, Bool) -> [TelegramMediaFileAttribute]) {
        self.fileAttributes = fileAttributes
    }

    private static var installed: CollageHooks?

    public static var shared: CollageHooks {
        guard let hooks = installed else {
            fatalError("CollageHooks.install must be called before collage checks are used")
        }
        return hooks
    }

    public static func install(_ hooks: CollageHooks) {
        installed = hooks
    }
}
