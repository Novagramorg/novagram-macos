struct WalletGiftProfileVisibility: Equatable {
    struct Update: Equatable {
        let slug: String
        let displayed: Bool
    }

    private var metadata: [String: Bool] = [:]
    private var confirmed: [String: Bool] = [:]
    private(set) var pending: Update?

    func displayed(_ slug: String) -> Bool? {
        return confirmed[slug] ?? metadata[slug]
    }

    mutating func receive(slug: String, displayed: Bool) {
        metadata[slug] = displayed
    }

    mutating func begin(slug: String) -> Update? {
        guard pending == nil, let displayed = displayed(slug) else { return nil }
        let update = Update(slug: slug, displayed: !displayed)
        pending = update
        return update
    }

    mutating func finish(_ update: Update, succeeded: Bool) {
        guard pending == update else { return }
        pending = nil
        if succeeded {
            confirmed[update.slug] = update.displayed
        }
    }
}
