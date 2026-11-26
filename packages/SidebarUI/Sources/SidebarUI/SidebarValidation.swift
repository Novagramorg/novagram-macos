import TelegramCore
import InputDataUI
import InputView
import InAppSettings
import Localization

func sidebarUpdatingTitle(_ filter: ChatListFilter, state: Updated_ChatTextInputState, animated: Bool, entities: (Updated_ChatTextInputState) -> [MessageTextEntity]) -> ChatListFilter {
    return filter.withUpdatedTitle(string: state.string, entities: entities(state), enableAnimations: animated)
}

func sidebarConfirmDiscard(changed: Bool, confirm: (@escaping () -> Void) -> Void, continuation: @escaping (Bool) -> Void) {
    if changed {
        confirm { continuation(true) }
    } else {
        continuation(true)
    }
}

func sidebarValidateFolder(filter: ChatListFilter, initialFilter: ChatListFilter, titleLength: Int, nameId: InputDataIdentifier, includeId: InputDataIdentifier, notify: (String) -> Void, requestSave: (@escaping () -> Void) -> Void, save: @escaping (Bool) -> Void, completion: @escaping (InputDataValidation) -> Void) {
    if titleLength == 0 || titleLength > 12 {
        completion(.fail(.fields([nameId: .shake])))
        return
    }
    if filter.isFullfilled {
        notify(strings().chatListFilterErrorLikeChats)
    } else if filter.isEmpty {
        notify(strings().chatListFilterErrorEmpty)
        completion(.fail(.fields([includeId: .shake])))
    } else if initialFilter != filter {
        requestSave {
            save(true)
            completion(.success(.navigationBack))
        }
    } else {
        save(false)
        completion(.success(.navigationBack))
    }
}
