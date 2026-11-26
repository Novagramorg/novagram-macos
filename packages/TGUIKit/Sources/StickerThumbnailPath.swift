import Foundation

private let decodingMap = Array("AACAAAAHAAALMAAAQASTAVAAAZaacaaaahaaalmaaaqastava.az0123456789-,".utf8)

private func stickerThumbnailPathLength(_ input: UnsafeRawBufferPointer) -> Int {
    var count = 2
    for byte in input {
        if byte >= 192 {
            count += 1
        } else {
            count += (byte & 63) < 10 ? 1 : 2
            if byte >= 64 {
                count += 1
            }
        }
    }
    return count
}

private func writeStickerThumbnailPath(_ input: UnsafeRawBufferPointer, to output: UnsafeMutableBufferPointer<UInt8>) -> Int {
    var index = 0
    output[index] = UInt8(ascii: "M")
    index += 1
    for byte in input {
        if byte >= 192 {
            output[index] = decodingMap[Int(byte) - 192]
            index += 1
        } else {
            if byte >= 128 {
                output[index] = UInt8(ascii: ",")
                index += 1
            } else if byte >= 64 {
                output[index] = UInt8(ascii: "-")
                index += 1
            }
            let value = byte & 63
            if value >= 10 {
                output[index] = UInt8(ascii: "0") + value / 10
                index += 1
            }
            output[index] = UInt8(ascii: "0") + value % 10
            index += 1
        }
    }
    output[index] = UInt8(ascii: "z")
    return index + 1
}

private func stickerThumbnailPathFallback(_ input: UnsafeRawBufferPointer, length: Int) -> String {
    var bytes = [UInt8](repeating: 0, count: length)
    bytes.withUnsafeMutableBufferPointer { output in
        _ = writeStickerThumbnailPath(input, to: output)
    }
    return String(decoding: bytes, as: UTF8.self)
}

func decodeStickerThumbnailData(_ data: Data) -> String {
    if data.isEmpty {
        return "Mz"
    }
    return data.withUnsafeBytes { (input: UnsafeRawBufferPointer) in
        let length = stickerThumbnailPathLength(input)
        if #available(macOS 11.0, *) {
            return String(unsafeUninitializedCapacity: length) { output in
                output.initialize(repeating: 0)
                return writeStickerThumbnailPath(input, to: output)
            }
        } else {
            return stickerThumbnailPathFallback(input, length: length)
        }
    }
}
