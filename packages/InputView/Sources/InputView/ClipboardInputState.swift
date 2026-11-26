import Cocoa
import Postbox
import TGUIKit

public func copyToClipboard(_ input: ChatTextInputState) -> Void {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.declareTypes([.kInApp, .string], owner: nil)

    let encoder = AdaptedPostboxEncoder()
    let encoded = try? encoder.encode(input)
    
    if let data = encoded {
        pb.setData(data, forType: .kInApp)
        pb.setString(input.inputText, forType: .string)
    }
}