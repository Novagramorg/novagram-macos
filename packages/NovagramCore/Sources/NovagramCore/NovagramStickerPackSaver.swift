//
//  NovagramStickerPackSaver.swift
//  NovagramCore
//
//  "Save All" for sticker and emoji packs, behind the Developer switch "Save sticker packs" (macOS only).
//  Asks for a folder, then saves every file of each pack in its own subfolder, in its original format
//  (.tgs animated, .webm video, .webp static), named by position and emoji: "001_😀.tgs".
//

import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramContext

public struct NovagramStickerPack {
    public let info: StickerPackCollectionInfo
    public let items: [StickerPackItem]

    public init(info: StickerPackCollectionInfo, items: [StickerPackItem]) {
        self.info = info
        self.items = items
    }
}

public enum NovagramStickerPackSaver {
    // A file that has not downloaded by then is counted as failed, so one stuck file can not hang the save.
    private static let downloadTimeout: Double = 60

    public static func save(_ packs: [NovagramStickerPack], context: any AccountContextProtocol) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = NovagramL10n.current.stickerPack_saveHere
        panel.beginSheetModal(for: context.window) { response in
            guard response == .OK, let folder = panel.url else {
                return
            }
            self.save(packs, into: folder, context: context)
        }
    }

    private static func save(_ packs: [NovagramStickerPack], into folder: URL, context: any AccountContextProtocol) {
        let window = context.window
        let l10n = NovagramL10n.current
        let mediaBox = context.account.postbox.mediaBox
        var jobs: [Signal<Bool, NoError>] = []
        var packFolders: [URL] = []

        for pack in packs {
            let packFolder = folder.appendingPathComponent(self.folderName(for: pack.info), isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: packFolder, withIntermediateDirectories: true)
            } catch {
                jobs.append(contentsOf: pack.items.map { _ in Signal<Bool, NoError>.single(false) })
                continue
            }
            packFolders.append(packFolder)
            let packReference = StickerPackReference.id(id: pack.info.id.id, accessHash: pack.info.accessHash)
            for (index, item) in pack.items.enumerated() {
                let file = item.file._parse()
                let destination = packFolder.appendingPathComponent(self.fileName(for: item, file: file, index: index))
                jobs.append(self.saveFile(file, packReference: packReference, to: destination, mediaBox: mediaBox))
            }
        }
        guard !jobs.isEmpty else {
            return
        }

        showModalText(for: window, text: l10n.stickerPack_saving(jobs.count))
        _ = (combineLatest(jobs) |> deliverOnMainQueue).start(next: { results in
            let saved = results.filter { $0 }.count
            let failed = results.count - saved
            let text = failed == 0
                ? l10n.stickerPack_saved(saved, folder: folder.lastPathComponent)
                : l10n.stickerPack_savedWithFailures(saved, failed: failed)
            showModalText(for: window, text: text)
            if !packFolders.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(packFolders)
            }
        })
    }

    private static func saveFile(_ file: TelegramMediaFile, packReference: StickerPackReference, to destination: URL, mediaBox: MediaBox) -> Signal<Bool, NoError> {
        let reference = FileMediaReference.stickerPack(stickerPack: packReference, media: file)
        let fetch = fetchedMediaResource(
            mediaBox: mediaBox,
            userLocation: reference.userLocation,
            userContentType: reference.userContentType,
            reference: reference.resourceReference(file.resource)
        )
        let copied = mediaBox.resourceData(file.resource)
            |> filter { $0.complete }
            |> take(1)
            |> map { data -> Bool in
                return self.copy(path: data.path, to: destination)
            }
            |> timeout(self.downloadTimeout, queue: Queue.concurrentDefaultQueue(), alternate: .single(false))

        return Signal { subscriber in
            let fetchDisposable = fetch.start()
            let copyDisposable = copied.start(next: { saved in
                subscriber.putNext(saved)
                subscriber.putCompletion()
            })
            return ActionDisposable {
                fetchDisposable.dispose()
                copyDisposable.dispose()
            }
        }
    }

    private static func copy(path: String, to destination: URL) -> Bool {
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: destination)
            return true
        } catch {
            return false
        }
    }

    private static func fileName(for item: StickerPackItem, file: TelegramMediaFile, index: Int) -> String {
        let number = String(format: "%03d", index + 1)
        let emoji = item.getStringRepresentationsOfIndexKeys().first.map { "_" + self.safeName($0) } ?? ""
        return number + emoji + "." + self.fileExtension(for: file)
    }

    private static func fileExtension(for file: TelegramMediaFile) -> String {
        switch file.mimeType {
        case "application/x-tgsticker":
            return "tgs"
        case "video/webm":
            return "webm"
        case "image/webp":
            return "webp"
        case "image/png":
            return "png"
        default:
            let fromName = (file.fileName.map { ($0 as NSString).pathExtension }) ?? ""
            return fromName.isEmpty ? "bin" : fromName
        }
    }

    private static func folderName(for info: StickerPackCollectionInfo) -> String {
        let name = self.safeName(info.shortName.isEmpty ? info.title : info.shortName)
        return name.isEmpty ? "\(info.id.id)" : name
    }

    private static func safeName(_ name: String) -> String {
        return name.components(separatedBy: CharacterSet(charactersIn: "/:")).joined(separator: "_")
    }
}
