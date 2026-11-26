import Foundation

func compactDecodePaths() -> [(String, Data)] {
    func coordinate(_ value: Int, first: Bool, data: inout Data) {
        let prefix = first ? 0 : 128
        if value < 64 {
            data.append(UInt8(prefix + value))
        } else {
            data.append(contentsOf: [UInt8(prefix + value / 10), UInt8(value % 10)])
        }
    }
    var lines = Data([0, 128]), curves = Data([0, 128])
    for index in 0..<60 {
        lines.append(203)
        coordinate((index * 97) % 512, first: true, data: &lines)
        coordinate((index * 179) % 512, first: false, data: &lines)
    }
    for index in 0..<40 {
        curves.append(194)
        for argument in 0..<6 {
            coordinate((index * 97 + argument * 73) % 512, first: argument == 0, data: &curves)
        }
    }
    return [("compact_lines", lines), ("compact_curves", curves)]
}
