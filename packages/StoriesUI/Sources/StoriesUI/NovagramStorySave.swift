import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import FilePanels
import TelegramTheme
import Strings
import NovagramCore

// TelegramMediaUtils' saveAs(_:account:), plus the rating prompt count once the file is written.
func novagramSaveStory(_ file: TelegramMediaFile, account: Account) {
    let name = account.postbox.mediaBox.resourceData(file.resource) |> take(1) |> mapToSignal { data -> Signal<(String, String), NoError> in
        guard data.complete else {
            return .complete()
        }
        if let ext = file.fileName?.nsstring.pathExtension {
            return .single((data.path, ext))
        }
        let ext = data.path.nsstring.pathExtension
        return resourceType(mimeType: file.mimeType) |> map { type in
            if let type, type != "*" {
                return (data.path, type)
            }
            return (data.path, ext.isEmpty ? "file" : ext)
        }
    } |> deliverOnMainQueue

    _ = name.start(next: { path, ext in
        savePanel(file: path, ext: ext, for: mainWindow, defaultName: file.fileName, completion: { savedPath in
            if let savedPath, FileManager.default.fileExists(atPath: savedPath) {
                NovagramReviewPrompt.record(.storySave)
            }
        })
    })
}
