import Foundation
import TelegramCore
import Localization

public extension TelegramMediaPoll {
    var title: String {
        if isClosed {
            return strings().chatPollTypeClosed
        } else {
            switch self.kind {
            case .quiz:
                switch self.publicity {
                case .anonymous:
                    return strings().chatPollTypeAnonymousQuiz
                case .public:
                    return strings().chatPollTypeQuiz
                }
            case .poll:
                switch self.publicity {
                case .anonymous:
                    return strings().chatPollTypeAnonymous
                case .public:
                    return strings().chatPollTypePublic
                }
            }
        }
    }

    var isMultiple: Bool {
        switch kind {
        case let .poll(multipleAnswers):
            return multipleAnswers
        case let .quiz(multipleAnswers):
            return multipleAnswers
        }
    }

    var isQuiz: Bool {
        switch kind {
        case .poll:
            return false
        case .quiz:
            return true
        }
    }
}
