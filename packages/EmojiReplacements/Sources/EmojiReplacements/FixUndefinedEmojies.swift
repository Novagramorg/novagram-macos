import Cocoa
import Strings

public extension NSMutableAttributedString {
    func fixUndefinedEmojies() {
        
        func changeSymbol(_ from:String, to: String) -> Bool {
            let range = string.nsstring.range(of: from)
            if range.location != NSNotFound {
                self.replaceCharacters(in: range, with: to)
                return true
            }
            return false
        }

        let symbols:[(from: String, to: String)] = [(from: "✌", to: "✌️"), (from: "☺", to: "☺️"), (from: "☝", to: "☝️"), (from: "1⃣", to: "1️⃣"), (from: "2⃣", to: "2️⃣"), (from: "3⃣", to: "3️⃣"), (from: "4⃣", to: "4️⃣"), (from: "5⃣", to: "5️⃣"), (from: "6⃣", to: "6️⃣"), (from: "7⃣", to: "7️⃣"), (from: "8⃣", to: "8️⃣"), (from: "9⃣", to: "9️⃣"), (from: "0⃣", to: "0️⃣"), (from: "❤", to: "❤️"), (from: "☁", to: "☁️"), (from: "ℹ", to: "ℹ️"), (from: "✍", to: "✍️"), (from: "♥", to: "❤️"), (from: "⁉", to: "⁉️"), (from: "❣", to: "❣️"), (from: "⬅", to: "⬅️"), (from: "◻", to: "◻️"), (from: "➡", to: "➡️"), (from: "◼", to: "◼️")]
        for symbol in symbols {
            while changeSymbol(symbol.from, to: symbol.to) {
                
            }
        }
    }
}
