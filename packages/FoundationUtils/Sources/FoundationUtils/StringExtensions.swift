import Foundation

public extension String {
    var withoutColorizer: String {
        let str = String(self.unicodeScalars.filter {
            $0 != "\u{fe0f}"
        })
        return str
    }
}
