import Foundation
import Production
import Baseline

struct Measurement: Codable {
    let scenario: String
    let callsPerSample: Int
    let baselineMilliseconds: [Double]
    let candidateMilliseconds: [Double]
    let baselineMedianMilliseconds: Double
    let candidateMedianMilliseconds: Double
    let speedup: Double
    let checksum: Int64
}

struct Report: Codable {
    let operatingSystem: String
    let processors: Int
    let timezone: String
    let samples: Int
    let measurements: [Measurement]
}

@inline(never)
func measure(_ work: () -> Int64) -> (Double, Int64) {
    let start = DispatchTime.now().uptimeNanoseconds
    let checksum = work()
    return (Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000, checksum)
}

func compare(_ scenario: String, calls: Int, baseline: () -> Int64, candidate: () -> Int64) -> Measurement {
    precondition(baseline() == candidate(), "Output mismatch: \(scenario)")
    var before: [Double] = []
    var after: [Double] = []
    var checksum: Int64 = 0
    for round in 0 ..< 9 {
        let left: (Double, Int64)
        let right: (Double, Int64)
        if round % 2 == 0 {
            left = measure(baseline)
            right = measure(candidate)
        } else {
            right = measure(candidate)
            left = measure(baseline)
        }
        precondition(left.1 == right.1, "Output mismatch: \(scenario)")
        before.append(left.0)
        after.append(right.0)
        checksum &+= right.1
    }
    let beforeMedian = before.sorted()[before.count / 2]
    let afterMedian = after.sorted()[after.count / 2]
    return Measurement(scenario: scenario, callsPerSample: calls, baselineMilliseconds: before, candidateMilliseconds: after, baselineMedianMilliseconds: beforeMedian, candidateMedianMilliseconds: afterMedian, speedup: beforeMedian / afterMedian, checksum: checksum)
}

func dateWork(_ timestamps: [Int32], repetitions: Int, transform: (Int32) -> Int64) -> Int64 {
    var checksum: Int64 = 0
    for _ in 0 ..< repetitions {
        for timestamp in timestamps {
            checksum &+= transform(timestamp)
        }
    }
    return checksum
}

func spoilerWork(_ texts: [String], repetitions: Int, transform: (String, NSRange) -> String) -> Int64 {
    var checksum: Int64 = 0
    for _ in 0 ..< repetitions {
        for text in texts {
            let output = transform(text, NSRange(location: 0, length: text.utf16.count))
            checksum &+= Int64(output.utf16.count)
            checksum &+= Int64(output.utf16.first ?? 0)
        }
    }
    return checksum
}

if CommandLine.arguments.contains("--invalid-spoiler") {
    print("secret".spoiler(NSRange(location: 2, length: 100)))
} else {
    let clustered = (0 ..< 2000).map { Int32(1_735_689_600 + $0 * 60) }
    let scattered = (0 ..< 1200).map { Int32(-2_000_000_000 + $0 * 3_000_000) }
    var measurements: [Measurement] = []
    for (name, timestamps, repetitions) in [("clustered", clustered, 10), ("scattered", scattered, 1)] {
        measurements.append(compare("day-\(name)", calls: timestamps.count * repetitions, baseline: {
            dateWork(timestamps, repetitions: repetitions, transform: legacyChatDateId)
        }, candidate: {
            dateWork(timestamps, repetitions: repetitions, transform: chatDateId)
        }))
        measurements.append(compare("month-\(name)", calls: timestamps.count * repetitions, baseline: {
            dateWork(timestamps, repetitions: repetitions, transform: legacyMediaDateId)
        }, candidate: {
            dateWork(timestamps, repetitions: repetitions, transform: mediaDateId)
        }))
    }
    for length in [16, 256, 4096] {
        let texts = [String(repeating: "s", count: length), String(repeating: "🙂", count: length / 2), String(repeating: "я", count: length)]
        let repetitions = length == 4096 ? 100 : 1000
        measurements.append(compare("spoiler-\(length)-utf16", calls: texts.count * repetitions, baseline: {
            spoilerWork(texts, repetitions: repetitions) { $0.legacySpoiler($1) }
        }, candidate: {
            spoilerWork(texts, repetitions: repetitions) { $0.spoiler($1) }
        }))
    }
    let longText = String(repeating: "some secret 🙂 ", count: 300)
    measurements.append(compare("spoiler-short-range-in-long-text", calls: 1000, baseline: {
        spoilerWork([longText], repetitions: 1000) { text, _ in text.legacySpoiler(NSRange(location: 2000, length: 6)) }
    }, candidate: {
        spoilerWork([longText], repetitions: 1000) { text, _ in text.spoiler(NSRange(location: 2000, length: 6)) }
    }))
    for (count, strideLength) in [(500, 10), (2000, 2000), (2000, 10), (10000, 10)] {
        let messages = (0 ..< count).map { LabMessage(id: $0, group: $0 / 10) }
        let ids = Array(stride(from: 0, to: count, by: strideLength))
        for albums in [false, true] {
            let original = labLegacySelectedMessages(messages, ids: ids, includeAlbums: albums)
            let current = labSelectedMessages(messages, ids: ids, includeAlbums: albums)
            precondition(original.map(\.id) == current.map(\.id))
            measurements.append(compare("selection-\(count)-ids-\(ids.count)-albums-\(albums)", calls: 20, baseline: {
                var checksum: Int64 = 0
                for _ in 0 ..< 20 {
                    checksum &+= labLegacySelectedMessages(messages, ids: ids, includeAlbums: albums).reduce(0) { $0 + Int64($1.id) }
                }
                return checksum
            }, candidate: {
                var checksum: Int64 = 0
                for _ in 0 ..< 20 {
                    checksum &+= labSelectedMessages(messages, ids: ids, includeAlbums: albums).reduce(0) { $0 + Int64($1.id) }
                }
                return checksum
            }))
        }
    }
    let report = Report(operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString, processors: ProcessInfo.processInfo.activeProcessorCount, timezone: TimeZone.current.identifier, samples: 9, measurements: measurements)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(decoding: try encoder.encode(report), as: UTF8.self))
}
