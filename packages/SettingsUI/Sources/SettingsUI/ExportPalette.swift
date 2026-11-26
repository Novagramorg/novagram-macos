import Cocoa
import TGUIKit
import ColorPalette
import FilePanels

public func exportPalette(palette: ColorPalette, completion:((String?)->Void)? = nil) -> Void {
    let string = palette.toString
    let temp = NSTemporaryDirectory() + "tmac.palette"
    try? string.write(to: URL(fileURLWithPath: temp), atomically: true, encoding: .utf8)
    savePanel(file: temp, ext: "palette", for: mainWindow, defaultName: "\(palette.name).palette", completion: completion)
}
