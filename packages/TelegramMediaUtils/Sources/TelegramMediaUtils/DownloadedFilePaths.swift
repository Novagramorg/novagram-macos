import Foundation
import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
import InAppSettings
import TelegramTheme

public func copyToDownloads(_ file: TelegramMediaFile, postbox: Postbox, saveAnyway: Bool = false) -> Signal<String?, NoError>  {
    let path = downloadFilePath(file, postbox)
    return combineLatest(queue: resourcesQueue, path, downloadedFilePaths(postbox)) |> map { (expanded, paths) in
        guard case (let boxPath, var adopted)? = expanded else {
            return nil
        }
        let id = file.fileId
        if let path = paths.path(for: id), !saveAnyway {
            let lastModified = Int32(FileManager.default.modificationDateForFileAtPath(path: path.downloadedPath)?.timeIntervalSince1970 ?? 0)
            if fileSize(path.downloadedPath) == Int64(path.size), lastModified == path.lastModified {
                return path.downloadedPath
            }
        }
        var i:Int = 1
        let deletedPathExt = adopted.nsstring.deletingPathExtension
        while FileManager.default.fileExists(atPath: adopted, isDirectory: nil) {
            let ext = adopted.nsstring.pathExtension
            adopted = "\(deletedPathExt) (\(i)).\(ext)"
            i += 1
        }
        
        try? FileManager.default.copyItem(atPath: boxPath, toPath: adopted)

        let quarantineData = "does not really matter what is here".cString(using: String.Encoding.utf8)!
        _ = Int(strlen(quarantineData))
        
//        setxattr(adopted.cString(using: .utf8), "com.apple.quarantine", quarantineData, quarantineDataLength, 0, XATTR_CREATE)
        
        //removexattr(adopted.cString(using: .utf8), "com.apple.quarantine", 0)
        
        let lastModified = FileManager.default.modificationDateForFileAtPath(path: adopted)?.timeIntervalSince1970 ?? FileManager.default.creationDateForFileAtPath(path: adopted)?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        
        let fs = fileSize(boxPath)
        let fileSize = fs ?? file.size ?? 0
        let path = DownloadedPath(id: id, downloadedPath: adopted, size: Int64(fileSize), lastModified: Int32(lastModified))
        
        _ = updateDownloadedFilePaths(postbox, {
            $0.withAddedPath(path)
        }).start()
        
        return adopted
    }
    
//    return downloadFilePath(file, postbox) |> deliverOn(resourcesQueue) |> map { (boxPath, adopted) in
//        var adopted = adopted
//        var i:Int = 1
//        let deletedPathExt = adopted.nsstring.deletingPathExtension
//        while FileManager.default.fileExists(atPath: adopted, isDirectory: nil) {
//            let ext = adopted.nsstring.pathExtension
//            let box = FileManager.xattrStringValue(forKey: TelegramFileMediaBoxPath, at: URL(fileURLWithPath: adopted))
//            if box == boxPath {
//                return
//            }
//
//            adopted = "\(deletedPathExt) (\(i)).\(ext)"
//            i += 1
//        }
//
//        try? FileManager.default.copyItem(atPath: boxPath, toPath: adopted)
//        FileManager.setXAttrStringValue(boxPath, forKey: TelegramFileMediaBoxPath, at: URL(fileURLWithPath: adopted))
//    }
//
}

public func downloadFilePath(_ file: TelegramMediaFile, _ postbox: Postbox) -> Signal<(String, String)?, NoError> {
    return combineLatest(postbox.mediaBox.resourceData(file.resource), automaticDownloadSettings(postbox: postbox)) |> take(1) |> mapToSignal { data, settings -> Signal< (String, String)?, NoError> in
        if data.complete {
            let fileName = (file.fileName ?? data.path.nsstring.lastPathComponent).fixedFileName
            var ext = fileName.nsstring.pathExtension
            if ext.isEmpty {
                ext = fileExt(file.mimeType) ?? ""
            }
            if !ext.isEmpty {
                return .single((data.path, "\(settings.downloadFolder)/\(fileName.nsstring.deletingPathExtension).\(ext)"))
            } else {
                return .single((data.path, "\(settings.downloadFolder)/\(fileName.nsstring.deletingPathExtension)"))
            }
        } else {
            return .single(nil)
        }
    }
}

public func fileFinderPath(_ file: TelegramMediaFile, _ postbox: Postbox) -> Signal<String?, NoError> {
    return combineLatest(downloadFilePath(file, postbox), downloadedFilePaths(postbox)) |> map { (expanded, paths) in
        guard let (_, adopted) = expanded else {
            return nil
        }
        if let id = file.id {
            do {
                
                if let path = paths.path(for: id) {
                    let lastModified = Int32(FileManager.default.modificationDateForFileAtPath(path: path.downloadedPath)?.timeIntervalSince1970 ?? 0)
                    if fileSize(path.downloadedPath) == Int64(path.size), lastModified == path.lastModified {
                       return path.downloadedPath
                    }
                }
                
                return adopted
            }
        } else {
            return nil
        }
    }
}
