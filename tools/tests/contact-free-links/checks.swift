
var checked = 0
for domain in ["t.me", "telegram.me", "telegram.dog"] {
    for prefix in ["", "https://", "http://"] {
        let link = "\(prefix)\(domain)/contact/XXXX:YYYZZZ?free=AbC%2B123%3D"
        precondition(parseContactTokenLink(link) == ContactTokenLink(token: "XXXX:YYYZZZ", freeToken: "AbC+123="))
        checked += 1
    }
}
for link in ["tg://contact?token=XXXX%3AYYYZZZ&free=AbC%2B123%3D", "TG://contact?free=AbC%2B123%3D&token=XXXX:YYYZZZ"] {
    precondition(parseContactTokenLink(link) == ContactTokenLink(token: "XXXX:YYYZZZ", freeToken: "AbC+123="))
    checked += 1
}
for link in ["https://t.me/contact/XXXX:YYYZZZ", "tg://contact?token=XXXX:YYYZZZ", "tg://contact?token=XXXX:YYYZZZ&free=", "https://t.me/contact/XXXX:YYYZZZ?free"] {
    precondition(parseContactTokenLink(link) == ContactTokenLink(token: "XXXX:YYYZZZ", freeToken: nil))
    checked += 1
}
for link in ["https://evil.test/contact/token?free=secret", "https://t.me.evil.test/contact/token", "https://t.me@evil.test/contact/token", "https://evil.test@t.me/contact/token", "https://t.me/contact/", "https://t.me/contact/a/b", "https://t.me/contact/a%2Fb", "tg://contact?token=", "tg://contacts?token=a", "tg://contact/other?token=a", "https://t.me/user?free=a"] {
    precondition(parseContactTokenLink(link) == nil, link)
    checked += 1
}
for action in [QrStudioCodeAction.expire, .permanent, .restore, .renew] {
    precondition(action.constrained(toTemporary: false) == action)
    precondition(action.constrained(toTemporary: true) == (action == .permanent ? .expire : action))
    checked += 2
}
var state = QrStudioCodeState()
precondition(QrStudioBurn.menu(for: state, allowsPermanent: false).isEmpty)
state.perform(QrStudioCodeAction.permanent.constrained(toTemporary: true), at: 10)
precondition(state.removeFee && state.expires)
precondition(QrStudioBurn.menu(for: state, allowsPermanent: false) == [[.renew], [.restore]])
precondition(QrStudioBurn.menu(for: state) == [[.renew, .permanent], [.restore]])
state.perform(.restore, at: 20)
precondition(!state.removeFee)
checked += 5
print("Passed \(checked) contact-link and temporary-code checks")
