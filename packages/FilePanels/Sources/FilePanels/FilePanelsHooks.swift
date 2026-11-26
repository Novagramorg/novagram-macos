import Foundation

public struct FilePanelsHooks {
    public let showSavedPathSuccess: (String) -> Void

    public init(showSavedPathSuccess: @escaping (String) -> Void) {
        self.showSavedPathSuccess = showSavedPathSuccess
    }

    private static var installed: FilePanelsHooks?

    public static var shared: FilePanelsHooks? {
        return installed
    }

    public static func install(_ hooks: FilePanelsHooks) {
        installed = hooks
    }
}
