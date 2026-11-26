import Foundation
import SwiftSignalKit

@available(macOS 10.15, *)
public final class FileDownload: NSObject, URLSessionDownloadDelegate {
    private let fileSize: Int64?
    private var urlSession: URLSession!
    private var completion: ((URL?, Error?) -> Void)?
    private var progressHandler: ((Double) -> Void)?
    
    public init(from url: URL, fileSize: Int64?, progressHandler: @escaping (Double) -> Void, completion: @escaping (URL?, Error?) -> Void) {
        self.progressHandler = progressHandler
        self.fileSize = fileSize
        self.completion = completion
        
        
        super.init()
        
        let configuration = URLSessionConfiguration.default
        urlSession = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
        
        let downloadTask = self.urlSession.downloadTask(with: url)
        downloadTask.resume()
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        var totalBytesExpectedToWrite = totalBytesExpectedToWrite
        if totalBytesExpectedToWrite == -1, let fileSize = self.fileSize {
            totalBytesExpectedToWrite = fileSize
        }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler?(progress)
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        completion?(location, nil)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completion?(nil, error)
        }
    }
    
    public static func getFileSize(url: String) -> Signal<Int64?, NoError> {
        if #available(macOS 14.0, *) {
            guard let url = URL(string: url) else {
                return .single(nil)
            }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            
            return Signal { subscriber in
                let task = URLSession.shared.dataTask(with: request) { _, response, error in
                    if let _ = error {
                        subscriber.putNext(nil)
                        subscriber.putCompletion()
                        return
                    }
                    var fileSize: Int64?
                    if let httpResponse = response as? HTTPURLResponse, let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"), let size = Int64(contentLength) {
                        fileSize = size
                    }
                    subscriber.putNext(fileSize)
                    subscriber.putCompletion()
                }
                task.resume()
                return ActionDisposable {
                    task.cancel()
                }
            }
        } else {
            return .single(nil)
        }
    }
}
