import Foundation

struct PanelEmojiSearchResult: Equatable {
    let values: [String]?
    let isLoading: Bool
}

enum PanelSearchPresentation: Equatable {
    case hidden
    case loading
    case empty

    static func resolve(isSearching: Bool, isLoading: Bool, hasResults: Bool) -> PanelSearchPresentation {
        guard isSearching && !hasResults else { return .hidden }
        return isLoading ? .loading : .empty
    }
}

enum PanelSearchPlaceholderKind {
    case emoji
    case stickers
    case gifs

    func frames(in size: CGSize) -> [CGRect] {
        guard size.width >= 64, size.height >= 40 else { return [] }
        let columns: Int
        let gap: CGFloat
        let height: CGFloat
        switch self {
        case .emoji:
            columns = max(1, Int((size.width - 32) / 42))
            gap = 16
            height = 28
        case .stickers:
            columns = max(1, Int((size.width - 32) / 90))
            gap = 18
            height = 76
        case .gifs:
            columns = 2
            gap = 10
            height = 92
        }
        let width = min((size.width - 32 - CGFloat(columns - 1) * gap) / CGFloat(columns), self == .emoji ? 28 : 160)
        let totalWidth = CGFloat(columns) * width + CGFloat(columns - 1) * gap
        let rows = min(4, max(1, Int((size.height - 24) / (height + gap))))
        var frames: [CGRect] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let rect = CGRect(x: floor((size.width - totalWidth) / 2) + CGFloat(column) * (width + gap), y: 20 + CGFloat(row) * (height + gap), width: width, height: min(height, size.height - 20))
                if rect.maxY <= size.height { frames.append(rect) }
            }
        }
        return frames
    }
}
