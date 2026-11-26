import Cocoa


public func rangeOfSearch(_ query: String, in text: String) -> NSRange? {
    
    guard !text.isEmpty && !query.isEmpty else {
        return nil
    }
    
    let range = text.lowercased().nsstring.range(of: query.lowercased())
    
    if range.location != NSNotFound {
        return range
    } else {
        return nil
    }
//
//    let query = (query.components(separatedBy: " ").max(by: { $0.count < $1.count}) ?? query).lowercased().trimmed.nsstring
//    let text = text.lowercased().nsstring
//    var start: Int = -1
//    var length: Int = -1
//    let N1 = text.length
//    for a in 0 ..< N1 {
//        var currentLen:Int = 0
//        let N2 = min(query.length, N1 - a)
//        loop: for b in 0 ..< N2 {
//            let match = text.character(at: a + b) == query.character(at: b)
//            if match {
//                currentLen += 1
//            }
//            if !match || b == N2 - 1 {
//                if currentLen > 0 && currentLen > length {
//                    length = currentLen
//                    start = a
//                }
//                break loop
//            }
//        }
//    }
//    if start == -1 {
//        return nil
//    }
//    let punctuationsChars = " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
//    loop: for a in start + length ..< text.length {
//        if !punctuationsChars.contains(text.substring(with: NSMakeRange(a, 1))) {
//            length += 1
//        } else {
//            break loop
//        }
//    }
//
//    return start != NSNotFound ? NSMakeRange(start, length) : nil
    
    
    
}
