import Cocoa
import SwiftSignalKit
import TGUIKit
fileprivate var mimestore:[String:String] = [:]
fileprivate var extensionstore:[String:String] = [:]


public func initializeMimeStore() {
    assertOnMainThread()
    if mimestore.isEmpty && extensionstore.isEmpty {
        let path = Bundle.main.path(forResource: "mime-types", ofType: "txt")
        let content = try? String(contentsOfFile: path ?? "")
        let mimes = content?.components(separatedBy: CharacterSet.newlines)
        
        if let mimes = mimes {
            for mime in mimes {
                let single = mime.components(separatedBy: ":")
                if single.count == 2 {
                    extensionstore[single[0]] = single[1]
                    mimestore[single[1]] = single[0]
                }
            }
        }
    }
}

public func resourceType(mimeType:String? = nil, orExt:String? = nil) -> Signal<String?, NoError> {
    
    
    assert(mimeType != nil || orExt != nil)
    assert((mimeType != nil && orExt == nil) || (mimeType == nil && orExt != nil))
    
    return Signal<String?, NoError> { (subscriber) -> Disposable in
        
        initializeMimeStore()
        
        var result:String?
        
        if let mimeType = mimeType {
            result = mimestore[mimeType]
        } else if let orExt = orExt {
            result = extensionstore[orExt.lowercased()]
        }
        
        subscriber.putNext(result)
        subscriber.putCompletion()
        
        return EmptyDisposable
        
    } |> runOn(Queue.mainQueue())
}

public func MIMEType(_ path: String, isExt: Bool = false) -> String {
    let fileExtension = isExt ? path.lowercased() : path.nsstring.pathExtension.lowercased()
    if !fileExtension.isEmpty {
        if let ext = extensionstore[fileExtension] {
            return ext
        } else {
            if !fileExtension.isEmpty {
                let UTIRef = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileExtension as CFString, nil)
                let UTI = UTIRef?.takeRetainedValue()
                if let UTI = UTI {
                    let MIMETypeRef = UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType)
                    if MIMETypeRef != nil
                    {
                        let MIMEType = MIMETypeRef?.takeRetainedValue()
                        return MIMEType as String? ?? "application/octet-stream"
                    }
                }
                
            }
            return "application/octet-stream"
        }
    } else {
        return !isExt && path.isDirectory ? "application/zip" : "application/octet-stream"
    }
    
}

public func fileExt(_ mimeType: String) -> String? {
    if let ext = mimestore[mimeType] {
        return ext
    }
    return nil
}

public let voiceMime = "audio/ogg"