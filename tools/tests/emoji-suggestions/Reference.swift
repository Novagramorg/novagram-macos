func referenceRecentEmojiSuggestions(emojis: [String], recentAnimated: [MediaId], animated: [TelegramMediaFile.Accessor]) -> (emojis: [String], animated: [TelegramMediaFile]) {
    var toRemove: [String] = []
    var selected: [TelegramMediaFile] = []
    for sort in recentAnimated {
        let file = animated.filter({ $0.fileId == sort}).first
        if let file = file?._parse() {
            selected.append(file)
            if let text = file.customEmojiText {
                toRemove.append(text.fixed)
            }
        }
    }
    let emojies = emojis.filter { value in
        return !toRemove.contains(value.fixed)
    }
    return (emojies, selected)
}

func referenceEmojiCandidates(_ installed: [TelegramMediaFile.Accessor], _ featured: [FeaturedPack]) -> [TelegramMediaFile.Accessor] {
    let build: ([TelegramMediaFile.Accessor], [FeaturedPack]) -> [TelegramMediaFile.Accessor] = {
        Array($0 + $1.reduce([], { current, value in
            return current + value.topItems.map { $0.file }
        }).prefix(400))
    }
    return build(installed, featured)
}
