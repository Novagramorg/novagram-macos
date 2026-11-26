import Foundation
import TelegramCore

extension RequestWebViewResult : @retroactive Equatable {
    public static func == (lhs: RequestWebViewResult, rhs: RequestWebViewResult) -> Bool {
        return lhs.queryId == rhs.queryId  && lhs.flags == rhs.flags && lhs.url == rhs.url
    }
}
