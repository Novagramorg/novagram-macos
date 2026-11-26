import Vision
import SwiftSignalKit
import Cocoa
import Postbox
import TelegramCore
import Translate


@available(macOS 10.15, *)
public final class TextRecognizing {
    
    public struct Point : Codable, Equatable {
        let _x: String
        let _y: String
        init(_ point: CGPoint) {
            self._x = "\((point.x))"
            self._y = "\((point.y))"
        }
        var x: CGFloat {
            if let float = Float(_x) {
                return CGFloat(float)
            } else {
                return 0
            }
        }
        var y: CGFloat {
            if let float = Float(_y) {
                return CGFloat(float)
            } else {
                return 0
            }
        }
    }
    public struct Size : Codable, Equatable {
        let _width: String
        let _height: String
        init(_ size: CGSize) {
            self._width = "\(size.width)"
            self._height = "\(size.height)"
        }
        var width: CGFloat {
            if let float = Float(_width) {
                return CGFloat(float)
            } else {
                return 0
            }
        }
        var height: CGFloat {
            if let float = Float(_height) {
                return CGFloat(float)
            } else {
                return 0
            }
        }
    }
    public struct Rect : Codable, Equatable {
        let origin: Point
        let size: Size
        init(_ rect: CGRect) {
            self.origin = Point(rect.origin)
            self.size = Size(rect.size)
        }
    }

    
    private static let queue = Queue(name: "org.telegram.Vision", qos: .background)
    public enum Error : Equatable {
        case generic
    }
    
    public enum TranslateResult : Equatable {
        public struct Value : Equatable {
            let text: String
            let detected: Result.Detected
            public init(text: String, detected: Result.Detected) {
                self.text = text
                self.detected = detected
            }
        }
        case progress(Result)
        case success(translated: [Value], original: Result)
    }
    
    public enum Result : Equatable {
        
        public struct Detected : Codable, Equatable {
            public var text: String
            public var language: String?
            
            fileprivate let _topLeft: Point
            fileprivate let _topRight: Point
            fileprivate let _bottomLeft: Point
            fileprivate let _bottomRight: Point
            fileprivate let _boundingBox: Rect
            
            public var topLeft: CGPoint {
                return CGPoint(x: _topLeft.x, y: _topLeft.y)
            }
            public var topRight: CGPoint {
                return CGPoint(x: _topRight.x, y: _topRight.y)
            }
            public var bottomLeft: CGPoint {
                return CGPoint(x: _bottomLeft.x, y: _bottomLeft.y)
            }
            public var bottomRight: CGPoint {
                return CGPoint(x: _bottomRight.x, y: _bottomRight.y)
            }
            public var boundingBox: CGRect {
                let point = CGPoint(x: _boundingBox.origin.x, y: _boundingBox.origin.y)
                let size = CGSize(width: _boundingBox.size.width, height: _boundingBox.size.height)
                return CGRect(origin: point, size: size)
            }
            public var rotationAngle: CGFloat {
                let deltaX = topRight.x - topLeft.x
                let deltaY = topRight.y - topLeft.y
                let rotation = atan2(deltaY, deltaX)
                if rotation > 0.03 {
                    return rotation
                } else {
                    return 0
                }
            }
            
            public var frameRect: CGRect {
                let width = distance(from: topLeft, to: topRight)
                let height = distance(from: topLeft, to: bottomLeft)
                
                let centerX = (topLeft.x + topRight.x + bottomLeft.x + bottomRight.x) / 4
                let centerY = (topLeft.y + topRight.y + bottomLeft.y + bottomRight.y) / 4
                let center = CGPoint(x: centerX, y: centerY)

                let originX = center.x - width / 2
                let originY = center.y - height / 2
                return CGRect(x: originX, y: originY, width: width, height: height)
            }

            private func distance(from point1: CGPoint, to point2: CGPoint) -> CGFloat {
                let dx = point2.x - point1.x
                let dy = point2.y - point1.y
                return sqrt(dx * dx + dy * dy)
            }
        }
        public struct Barcode : Codable, Equatable {
            public let payload: String

            fileprivate let _topLeft: Point
            fileprivate let _topRight: Point
            fileprivate let _bottomLeft: Point
            fileprivate let _bottomRight: Point

            public var topLeft: CGPoint {
                return CGPoint(x: _topLeft.x, y: _topLeft.y)
            }
            public var topRight: CGPoint {
                return CGPoint(x: _topRight.x, y: _topRight.y)
            }
            public var bottomLeft: CGPoint {
                return CGPoint(x: _bottomLeft.x, y: _bottomLeft.y)
            }
            public var bottomRight: CGPoint {
                return CGPoint(x: _bottomRight.x, y: _bottomRight.y)
            }

            init(payload: String, topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) {
                self.payload = payload
                self._topLeft = Point(topLeft)
                self._topRight = Point(topRight)
                self._bottomLeft = Point(bottomLeft)
                self._bottomRight = Point(bottomRight)
            }

            public var link: String? {
                let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https", "tg", "ton", "mailto"].contains(scheme) {
                    return trimmed
                }
                guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
                    return nil
                }
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                let matches = detector.matches(in: trimmed, options: [], range: range)
                if matches.count == 1, let match = matches.first, match.range == range, let url = match.url {
                    return url.absoluteString
                }
                return nil
            }
        }

        case progress(Double)
        case finish(image: CGImage, text: [Detected], barcodes: [Barcode])
        
        var inProgress: Bool {
            switch self {
            case .progress:
                return true
            default:
                return false
            }
        }
    }
    public static func recognize(_ cgImage: CGImage, postbox: Postbox?, stableId: MediaId?) -> Signal<Result, Error> {
        return Signal { subscriber in
            
            let requestHandler = VNImageRequestHandler(cgImage: cgImage)
            
            let actionDisposable = MetaDisposable()
            
            let request = VNRecognizeTextRequest()
            request.preferBackgroundProcessing = true
            request.usesLanguageCorrection = true
            request.recognitionLevel = .accurate
            if #available(macOS 13.0, *) {
                request.revision = VNRecognizeTextRequestRevision3
                request.automaticallyDetectsLanguage = true
            }
            
            request.progressHandler = { _, progress, _ in
                subscriber.putNext(.progress(progress))
            }
            
            let barcodeRequest = VNDetectBarcodesRequest()
            barcodeRequest.preferBackgroundProcessing = true
            barcodeRequest.symbologies = [.qr]
            
            let signal = Cache.get(postbox: postbox, stableId: stableId) |> deliverOn(queue)
            
            actionDisposable.set(signal.start(next: { cached in
                if let cached = cached, let barcodes = cached.barcodes {
                    subscriber.putNext(.finish(image: cgImage, text: cached.texts, barcodes: barcodes))
                    subscriber.putCompletion()
                    return
                }
                try? requestHandler.perform([barcodeRequest])
                do {
                    try requestHandler.perform([request])
                } catch {
                    subscriber.putError(.generic)
                    return
                }
                guard let observations = request.results else {
                    subscriber.putError(.generic)
                    return
                }
                var results:[Result.Detected] = []
                for observation in observations {
                    for text in observation.topCandidates(1) {
                        if text.confidence > 0.25 {
                            results.append(.init(text: text.string, language: Translate.detectLanguage(for: text.string), _topLeft: Point(observation.topLeft), _topRight: Point(observation.topRight), _bottomLeft: Point(observation.bottomLeft), _bottomRight: Point(observation.bottomRight), _boundingBox: Rect(observation.boundingBox)))
                        }
                    }
                }
                var barcodes:[Result.Barcode] = []
                for observation in barcodeRequest.results ?? [] {
                    if let payload = observation.payloadStringValue, !payload.isEmpty {
                        barcodes.append(.init(payload: payload, topLeft: observation.topLeft, topRight: observation.topRight, bottomLeft: observation.bottomLeft, bottomRight: observation.bottomRight))
                    }
                }
                subscriber.putNext(.finish(image: cgImage, text: results, barcodes: barcodes))
                subscriber.putCompletion()
                if let postbox = postbox, let stableId = stableId {
                    _ = Cache.set(postbox: postbox, texts: results, barcodes: barcodes, stableId: stableId).start()
                }
            }))
            
           
            return ActionDisposable {
                request.cancel()
                barcodeRequest.cancel()
                actionDisposable.dispose()
            }
        } |> runOn(queue)
    }
    
    

}


@available(macOS 10.15, *)
internal extension TextRecognizing {

    static let key = applicationSpecificPreferencesKey(1003)
    
    final class Cache {
        struct Data : Codable {
            let stableId: MediaId
            let texts:[Result.Detected]
            let barcodes:[Result.Barcode]?
        }
        private struct Entries : Codable {
            var list: [Data]
        }
        static func get(postbox: Postbox?, stableId: MediaId?) -> Signal<Data?, NoError> {
            if let postbox = postbox, let stableId = stableId {
                return postbox.transaction { transaction -> Data? in
                    let entries = transaction.getPreferencesEntry(key: key)?.get(Entries.self) ?? Entries(list: [])
                    return entries.list.first(where: {
                        $0.stableId == stableId
                    })
                }
            } else {
                return .single(nil)
            }
        }
        static func set(postbox: Postbox, texts:[Result.Detected], barcodes:[Result.Barcode], stableId: MediaId) -> Signal<Void, NoError> {
            return postbox.transaction { transaction -> Void in
                transaction.updatePreferencesEntry(key: key, { entry in
                    var entries = entry?.get(Entries.self) ?? Entries(list: [])
                    let entry = Data(stableId: stableId, texts: texts, barcodes: barcodes)
                    let index = entries.list.firstIndex(where: { $0.stableId == stableId})
                    if let index = index {
                        entries.list[index] = entry
                    } else {
                        entries.list.append(entry)
                    }
                    entries.list = Array(entries.list.suffix(100))
                    
                    return PreferencesEntry(entries)
                })
            }
        }
    }

}


