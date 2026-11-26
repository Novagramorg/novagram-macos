import Foundation

#if DEBUG

let chatGramsModalCommand = "/grams_modal"

func isChatGramsModalCommand(_ text: String) -> Bool {
    return text.trimmingCharacters(in: .whitespacesAndNewlines) == chatGramsModalCommand
}

#endif
