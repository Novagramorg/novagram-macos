import Cocoa

public func copyToClipboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.declareTypes([.string], owner: nil)
    NSPasteboard.general.setString(string, forType: .string)
}

public func copyToClipboard(_ url: URL, _ image: NSImage) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects([url as NSURL, image])
}
