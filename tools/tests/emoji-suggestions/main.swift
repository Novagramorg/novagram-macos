import Foundation

struct Generator {
    var seed: UInt64 = 120315

    mutating func next(_ limit: Int) -> Int {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Int((seed >> 32) % UInt64(limit))
    }
}

var comparisons = 0

func check(_ emojis: [String], _ recent: [MediaId], _ files: [TelegramMediaFile.Accessor]) {
    for accessor in files {
        accessor.file.parseCount = 0
    }
    let reference = referenceRecentEmojiSuggestions(emojis: emojis, recentAnimated: recent, animated: files)
    let referenceParseCounts = files.map { $0.file.parseCount }
    for accessor in files {
        accessor.file.parseCount = 0
    }
    let candidate = recentEmojiSuggestions(emojis: emojis, recentAnimated: recent, animated: files)
    precondition(reference.emojis == candidate.emojis, "Plain emoji order or contents changed")
    precondition(reference.animated.count == candidate.animated.count, "Animated emoji count changed")
    precondition(zip(reference.animated, candidate.animated).allSatisfy { $0 === $1 }, "Animated emoji identity or order changed")
    precondition(referenceParseCounts == files.map { $0.file.parseCount }, "Parsing count changed")
    comparisons += 1
}

let texts: [String?] = [nil, "", "😀", "😀", "❤️", "❤", "👍🏽", "👨‍👩‍👧‍👦", "é", "e\u{301}"]
let plain = texts.compactMap { $0 }
let alphabet = (0..<6).map {
    TelegramMediaFile.Accessor(file: TelegramMediaFile(id: $0 % 2, namespace: Int32($0 / 4), text: texts[$0]))
}
var fileLists: [[TelegramMediaFile.Accessor]] = [[]]
for first in alphabet {
    fileLists.append([first])
    for second in alphabet {
        fileLists.append([first, second])
        for third in alphabet {
            fileLists.append([first, second, third])
        }
    }
}
let ids = [MediaId(namespace: 0, id: 0), MediaId(namespace: 0, id: 1), MediaId(namespace: 1, id: 0), MediaId(namespace: 2, id: 99)]
var recentLists: [[MediaId]] = [[]]
for first in ids {
    recentLists.append([first])
    for second in ids {
        recentLists.append([first, second])
        recentLists.append([first, second, first, second, first])
    }
}
for files in fileLists {
    for recent in recentLists {
        check(plain, recent, files)
    }
}
var generator = Generator()
for _ in 0..<20000 {
    let files = (0..<generator.next(150)).map { _ in
        TelegramMediaFile.Accessor(file: TelegramMediaFile(id: generator.next(40), namespace: Int32(generator.next(3)), text: texts[generator.next(texts.count)]))
    }
    let recent = (0..<generator.next(40)).map { _ in
        MediaId(namespace: Int32(generator.next(3)), id: Int64(generator.next(45)))
    }
    let emojis = (0..<generator.next(60)).map { _ in plain[generator.next(plain.count)] }
    check(emojis, recent, files)
}
print("Passed \(comparisons) exact-result comparisons, including object identity and parse counts")

for trial in 0..<500 {
    let installed = (0..<generator.next(200)).map { _ in alphabet[generator.next(alphabet.count)] }
    let featured = (0..<generator.next(50)).map { _ in
        FeaturedPack(topItems: (0..<generator.next(60)).map { _ in FeaturedItem(alphabet[generator.next(alphabet.count)]) })
    }
    let expected = referenceEmojiCandidates(installed, featured)
    for pack in featured {
        for item in pack.topItems {
            item.reads = 0
        }
    }
    let actual = emojiCandidates(installed, featured)
    precondition(actual.count == expected.count, "Candidate count changed at trial \(trial)")
    precondition(zip(actual, expected).allSatisfy { $0.file === $1.file }, "Candidate identity or order changed at trial \(trial)")
    let reads = featured.reduce(0) { total, pack in total + pack.topItems.reduce(0) { $0 + $1.reads } }
    precondition(reads == min(400, featured.reduce(0) { $0 + $1.topItems.count }), "Extra featured files were read")
}
print("Passed 500 candidate-list comparisons; at most 400 featured files read")

var checksum = 0

@inline(never)
func measure(_ emojis: [String], _ recent: [MediaId], _ files: [TelegramMediaFile.Accessor], reference: Bool, repeats: Int) -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    for _ in 0..<repeats {
        let result = reference
            ? referenceRecentEmojiSuggestions(emojis: emojis, recentAnimated: recent, animated: files)
            : recentEmojiSuggestions(emojis: emojis, recentAnimated: recent, animated: files)
        checksum &+= result.emojis.count + result.animated.count
        checksum &+= Int(result.animated.last?.fileId.id ?? 0)
    }
    return Double(DispatchTime.now().uptimeNanoseconds - start) / Double(repeats) / 1000
}

if CommandLine.arguments.contains("--benchmark") {
    for available in [200, 600] {
        let files = (0..<available).map {
            TelegramMediaFile.Accessor(file: TelegramMediaFile(id: $0, text: plain[$0 % plain.count]))
        }
        for count in [0, 1, 2, 4, 8, 16, 32] {
            for location in ["front", "back", "missing"] {
                let recent = (0..<count).map { index in
                    MediaId(namespace: 0, id: Int64(location == "front" ? index : location == "back" ? available - 1 - index : available + index))
                }
                var referenceTimes: [Double] = []
                var candidateTimes: [Double] = []
                for run in 0..<8 {
                    for reference in (run % 2 == 0 ? [true, false] : [false, true]) {
                        let time = measure(plain, recent, files, reference: reference, repeats: 1000)
                        if run > 0 {
                            if reference {
                                referenceTimes.append(time)
                            } else {
                                candidateTimes.append(time)
                            }
                        }
                    }
                }
                let before = referenceTimes.sorted()[3]
                let after = candidateTimes.sorted()[3]
                print("available=\(available), recent=\(count), \(location): baseline=\(String(format: "%.2f", before))us optimized=\(String(format: "%.2f", after))us speedup=\(String(format: "%.2f", before / after))x")
            }
        }
    }
    for packCount in [5, 20, 100, 500] {
        let installed = (0..<200).map { TelegramMediaFile.Accessor(file: TelegramMediaFile(id: $0, text: nil)) }
        let featured = (0..<packCount).map { pack in
            FeaturedPack(topItems: (0..<20).map {
                FeaturedItem(TelegramMediaFile.Accessor(file: TelegramMediaFile(id: pack * 20 + $0, text: nil)))
            })
        }
        var beforeTimes: [Double] = []
        var afterTimes: [Double] = []
        for run in 0..<8 {
            for reference in (run % 2 == 0 ? [true, false] : [false, true]) {
                let start = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<100 {
                    let result = reference ? referenceEmojiCandidates(installed, featured) : emojiCandidates(installed, featured)
                    checksum &+= result.count
                    checksum &+= Int(result.last?.fileId.id ?? 0)
                }
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 100000
                if run > 0 {
                    if reference {
                        beforeTimes.append(elapsed)
                    } else {
                        afterTimes.append(elapsed)
                    }
                }
            }
        }
        let before = beforeTimes.sorted()[3]
        let after = afterTimes.sorted()[3]
        print("featured packs=\(packCount), files=\(packCount * 20): baseline=\(String(format: "%.2f", before))us optimized=\(String(format: "%.2f", after))us speedup=\(String(format: "%.2f", before / after))x")
    }
    print("checksum \(checksum)")
}
