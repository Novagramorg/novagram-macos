import Foundation
import Cocoa

final class PathDataReader {
    private var current: UInt8?
    private var previous: UInt8?
    private let input: String.UTF8View
    private var position: String.UTF8View.Index

    private static let spaces: Set<UInt8> = Set("\n\r\t ,".utf8)

    init(input: String) {
        self.input = input.utf8
        self.position = input.utf8.startIndex
    }

    public func read() -> [PathSegment] {
        readNext()
        var segments = [PathSegment]()
        while readSegments(into: &segments) {}
        return segments
    }

    private func readSegments(into result: inout [PathSegment]) -> Bool {
        if let type = readSegmentType() {
            let argCount = getArgCount(segment: type)
            if argCount == 0 {
                result.append(PathSegment(type: type))
                return true
            }
            var data = [Double]()
            var currentType = type
            let hasFlags = type == .a || type == .A
            while true {
                skipSpaces()
                let value = hasFlags && (data.count == 3 || data.count == 4) ? readFlag() : readNum()
                guard let value = value else {
                    return true
                }
                if data.isEmpty {
                    data.reserveCapacity(argCount)
                }
                data.append(value)
                if data.count == argCount {
                    result.append(PathSegment(type: currentType, data: data))
                    data = []
                    if type == .M {
                        currentType = .L
                    } else if type == .m {
                        currentType = .l
                    }
                }
            }
        }
        return false
    }

    private func skipSpaces() {
        var currentCharacter = current
        while let character = currentCharacter, Self.spaces.contains(character) {
            currentCharacter = readNext()
        }
    }

    private func readFlag() -> Double? {
        guard let ch = current else {
            return .none
        }
        readNext()
        switch ch {
        case UInt8(ascii: "0"):
            return 0
        case UInt8(ascii: "1"):
            return 1
        default:
            return .none
        }
    }

    fileprivate func readNum() -> Double? {
        guard let ch = current else {
            return .none
        }

        guard ch >= UInt8(ascii: "0") && ch <= UInt8(ascii: "9") || ch == UInt8(ascii: ".") || ch == UInt8(ascii: "-") else {
            return .none
        }

        let start = input.index(before: position)
        let negative = ch == UInt8(ascii: "-")
        var isInteger = ch != UInt8(ascii: ".")
        var magnitude: UInt64 = 0
        var digits = 0
        if ch >= UInt8(ascii: "0") && ch <= UInt8(ascii: "9") {
            magnitude = UInt64(ch - UInt8(ascii: "0"))
            digits = 1
        }
        var hasDot = ch == UInt8(ascii: ".")
        while let next = readDigit(&hasDot) {
            if isInteger && next >= UInt8(ascii: "0") && next <= UInt8(ascii: "9") && digits < 15 {
                magnitude = magnitude * 10 + UInt64(next - UInt8(ascii: "0"))
                digits += 1
            } else {
                isInteger = false
            }
        }
        if isInteger && digits != 0 {
            return negative ? -Double(magnitude) : Double(magnitude)
        }
        let end = current == nil ? position : input.index(before: position)
        return Double(String(decoding: input[start..<end], as: UTF8.self))
    }

    fileprivate func readDigit(_ hasDot: inout Bool) -> UInt8? {
        if let ch = readNext() {
            if (ch >= UInt8(ascii: "0") && ch <= UInt8(ascii: "9")) || ch == UInt8(ascii: "e") || (previous == UInt8(ascii: "e") && ch == UInt8(ascii: "-")) {
                return ch
            } else if ch == UInt8(ascii: ".") && !hasDot {
                hasDot = true
                return ch
            }
        }
        return nil
    }

    @discardableResult
    private func readNext() -> UInt8? {
        previous = current
        if position == input.endIndex {
            current = nil
        } else {
            current = input[position]
            input.formIndex(after: &position)
        }
        return current
    }

    private func readSegmentType() -> PathSegment.SegmentType? {
        while true {
            if let type = getPathSegmentType() {
                readNext()
                return type
            }
            if readNext() == nil {
                return nil
            }
        }
    }

    fileprivate func getPathSegmentType() -> PathSegment.SegmentType? {
        if let ch = current {
            switch ch {
            case UInt8(ascii: "M"):
                return .M
            case UInt8(ascii: "m"):
                return .m
            case UInt8(ascii: "L"):
                return .L
            case UInt8(ascii: "l"):
                return .l
            case UInt8(ascii: "C"):
                return .C
            case UInt8(ascii: "c"):
                return .c
            case UInt8(ascii: "Q"):
                return .Q
            case UInt8(ascii: "q"):
                return .q
            case UInt8(ascii: "A"):
                return .A
            case UInt8(ascii: "a"):
                return .a
            case UInt8(ascii: "z"), UInt8(ascii: "Z"):
                return .z
            case UInt8(ascii: "H"):
                return .H
            case UInt8(ascii: "h"):
                return .h
            case UInt8(ascii: "V"):
                return .V
            case UInt8(ascii: "v"):
                return .v
            case UInt8(ascii: "S"):
                return .S
            case UInt8(ascii: "s"):
                return .s
            case UInt8(ascii: "T"):
                return .T
            case UInt8(ascii: "t"):
                return .t
            default:
                break
            }
        }
        return nil
    }

    fileprivate func getArgCount(segment: PathSegment.SegmentType) -> Int {
        switch segment {
        case .H, .h, .V, .v:
            return 1
        case .M, .m, .L, .l, .T, .t:
            return 2
        case .S, .s, .Q, .q:
            return 4
        case .C, .c:
            return 6
        case .A, .a:
            return 7
        default:
            return 0
        }
    }
}
