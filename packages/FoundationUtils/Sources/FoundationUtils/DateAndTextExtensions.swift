import Foundation

public extension Date {
    var startOfDay: Date {
        let calendar = NSCalendar.current
        return calendar.startOfDay(for: self)
    }
    
    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        let calendar = NSCalendar.current
        return calendar.date(byAdding: components, to: startOfDay)!
    }
    
}

private let spoilerCharacters = Array("⠁⠂⠄⠈⠐⠠⡀⢀⠃⠅⠆⠉⠊⠌⠑⠒⠔⠘⠡⠢⠤⠨⠰⡁⡂⡄⡈⡐⡠⢁⢂⢄⢈⢐⢠⣀⠇⠋⠍⠎⠓⠕⠖⠙⠚⠜⠣⠥⠦⠩⠪⠬⠱⠲⠴⠸⡃⡅⡆⡉⡊⡌⡑⡒⡔⡘⡡⡢⡤⡨⡰⢃⢅⢆⢉⢊⢌⢑⢒⢔⢘⢡⢢⢤⢨⢰⣁⣂⣄⣈⣐⣠⠏⠗⠛⠝⠞⠧⠫⠭⠮⠳⠵⠶⠹⠺⠼⡇⡋⡍⡎⡓⡕⡖⡙⡚⡜⡣⡥⡦⡩⡪⡬⡱⡲⡴⡸⢇⢋⢍⢎⢓⢕⢖⢙⢚⢜⢣⢥⢦⢩⢪⢬⢱⢲⢴⢸⣃⣅⣆⣉⣊⣌⣑⣒⣔⣘⣡⣢⣤⣨⣰⠟⠯⠷⠻⠽⠾⡏⡗⡛⡝⡞⡧⡫⡭⡮⡳⡵⡶⡹⡺⡼⢏⢗⢛⢝⢞⢧⢫⢭⢮⢳⢵⢶⢹⢺⢼⣇⣋⣍⣎⣓⣕⣖⣙⣚⣜⣣⣥⣦⣩⣪⣬⣱⣲⣴⣸⠿⡟⡯⡷⡻⡽⡾⢟⢯⢷⢻⢽⢾⣏⣗⣛⣝⣞⣧⣫⣭⣮⣳⣵⣶⣹⣺⣼⡿⢿⣟⣯⣷⣻⣽⣾⣿".utf16)

public extension String {
    func spoiler(_ range: NSRange) -> String {
        guard range.location >= 0, range.location != NSNotFound, range.length > 0 else {
            return self
        }
        var characters = Array(self.utf16)
        guard range.location < characters.count else {
            return self
        }
        let length = min(range.length, characters.count - range.location)
        let mapping = spoilerCharacters
        for index in range.location ..< range.location + length {
            characters[index] = mapping[Int(characters[index]) % mapping.count]
        }
        return NSString(characters: characters, length: characters.count) as String
    }
}

public extension String {
    var fixed: String {
        let str: String = self
        return str
    }
}

public func makeNewDateFormatter() -> DateFormatter {
    return DateFormatter()
}
