import Foundation
import TGUIKit

public struct LinkHooks {
    public let callbackLink: (String, @escaping (String) -> Void) -> Any
    public let globalLinkExecutor: () -> TextViewInteractions
    public let openExternalLink: (String, Bool) -> Void
    public let markdownLink: (String) -> Any
    public let externalLink: (String, Bool) -> Any
    public let linkPayload: (Any) -> String?
    public let openAnyLink: (Any) -> Void
    public let detectLinks: (NSMutableAttributedString, ParsingType) -> Void

    public init(callbackLink: @escaping (String, @escaping (String) -> Void) -> Any,
                globalLinkExecutor: @escaping () -> TextViewInteractions,
                openExternalLink: @escaping (String, Bool) -> Void,
                markdownLink: @escaping (String) -> Any,
                externalLink: @escaping (String, Bool) -> Any,
                linkPayload: @escaping (Any) -> String?,
                openAnyLink: @escaping (Any) -> Void,
                detectLinks: @escaping (NSMutableAttributedString, ParsingType) -> Void) {
        self.callbackLink = callbackLink
        self.globalLinkExecutor = globalLinkExecutor
        self.openExternalLink = openExternalLink
        self.markdownLink = markdownLink
        self.externalLink = externalLink
        self.linkPayload = linkPayload
        self.openAnyLink = openAnyLink
        self.detectLinks = detectLinks
    }

    private static var installed: LinkHooks?

    public static var shared: LinkHooks {
        guard let hooks = installed else {
            fatalError("LinkHooks.install must be called before links are used")
        }
        return hooks
    }

    public static func install(_ hooks: LinkHooks) {
        installed = hooks
    }
}
