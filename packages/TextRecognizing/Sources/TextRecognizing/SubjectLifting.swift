import Foundation
import Cocoa
import Vision
import CoreImage
import SwiftSignalKit
import libwebp

public func stickerWebP(from image: CGImage) -> (data: Data, size: CGSize)? {
    let side: CGFloat = 512
    let scale = side / CGFloat(max(1, max(image.width, image.height)))
    let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
    let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let scaled = context.makeImage(), let data = convertToWebP(scaled, 90) else {
        return nil
    }
    return (data: data, size: CGSize(width: width, height: height))
}

@available(macOS 14.0, *)
public extension TextRecognizing {

    struct Subject {
        public let image: CGImage
        public let rect: CGRect
        
        public func stickerImage(outline: Bool = false) -> CGImage? {
            let side: CGFloat = 512
            let border: CGFloat = outline ? 10 : 0
            let scale = (side - border * 2) / CGFloat(max(image.width, image.height))
            let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
            let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
            let inset = Int(border)
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: width + inset * 2, height: height + inset * 2, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return nil
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: inset, y: inset, width: width, height: height))
            guard let scaled = context.makeImage() else {
                return nil
            }
            if outline {
                return Subject.outlined(scaled, width: border, colorSpace: colorSpace)
            }
            return scaled
        }

        public func stickerData(outline: Bool = false) -> Data? {
            guard let image = stickerImage(outline: outline) else {
                return nil
            }
            return convertToWebP(image, 90)
        }

        private static func outlined(_ image: CGImage, width: CGFloat, colorSpace: CGColorSpace) -> CGImage? {
            let input = CIImage(cgImage: image)
            let extent = input.extent
            let dilated = input.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: width]).cropped(to: extent)
            let border = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: extent).applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: dilated])
            let context = CIContext(options: [.workingColorSpace: colorSpace, .outputColorSpace: colorSpace])
            return context.createCGImage(input.composited(over: border), from: extent)
        }
    }

    private static let subjectQueue = Queue(name: "org.telegram.Vision.subject", qos: .userInitiated)
    
    static func liftSubject(_ cgImage: CGImage, at point: CGPoint?) -> Signal<Subject?, NoError> {
        return Signal { subscriber in
            let cgImage = limitedImage(cgImage, maxSide: 2560)
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNGenerateForegroundInstanceMaskRequest()

            do {
                try handler.perform([request])
            } catch {
                subscriber.putNext(nil)
                subscriber.putCompletion()
                return EmptyDisposable
            }

            guard let observation = request.results?.first else {
                subscriber.putNext(nil)
                subscriber.putCompletion()
                return EmptyDisposable
            }

            let instances = subjectInstances(observation, at: point)
            guard !instances.isEmpty, let buffer = try? observation.generateMaskedImage(ofInstances: instances, from: handler, croppedToInstancesExtent: false) else {
                subscriber.putNext(nil)
                subscriber.putCompletion()
                return EmptyDisposable
            }

            subscriber.putNext(makeSubject(buffer))
            subscriber.putCompletion()

            return ActionDisposable {
                request.cancel()
            }
        } |> runOn(subjectQueue)
    }

    private static func limitedImage(_ image: CGImage, maxSide: Int) -> CGImage {
        let side = max(image.width, image.height)
        guard side > maxSide else {
            return image
        }
        let scale = CGFloat(maxSide) / CGFloat(side)
        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
    
    private static func subjectInstances(_ observation: VNInstanceMaskObservation, at point: CGPoint?) -> IndexSet {
        let all = observation.allInstances
        guard let point else {
            return all
        }
        let mask = observation.instanceMask
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(mask, .readOnly)
        }
        guard let base = CVPixelBufferGetBaseAddress(mask) else {
            return all
        }
        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)
        let x = min(width - 1, max(0, Int(point.x * CGFloat(width))))
        let y = min(height - 1, max(0, Int((1 - point.y) * CGFloat(height))))
        let label = Int(base.load(fromByteOffset: y * bytesPerRow + x, as: UInt8.self))
        if label != 0, all.contains(label) {
            return IndexSet(integer: label)
        }
        return all
    }

    private static func makeSubject(_ buffer: CVPixelBuffer) -> Subject? {
        let ciImage = CIImage(cvPixelBuffer: buffer)
        let context = CIContext(options: nil)
        guard let full = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        let width = full.width
        let height = full.height
        guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        let bytesPerRow = width * 4
        guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        bitmap.draw(full, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = bitmap.data else {
            return nil
        }
        let pixels = data.bindMemory(to: UInt8.self, capacity: bitmap.bytesPerRow * height)
        let rowBytes = bitmap.bytesPerRow

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for row in 0 ..< height {
            let offset = row * rowBytes
            var rowHasAlpha = false
            for column in 0 ..< width where pixels[offset + column * 4 + 3] > 8 {
                rowHasAlpha = true
                minX = min(minX, column)
                maxX = max(maxX, column)
            }
            if rowHasAlpha {
                minY = min(minY, row)
                maxY = max(maxY, row)
            }
        }
        guard maxX >= minX, maxY >= minY else {
            return nil
        }

        let crop = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let image = bitmap.makeImage()?.cropping(to: crop) else {
            return nil
        }
        let rect = CGRect(x: crop.minX / CGFloat(width), y: 1 - crop.maxY / CGFloat(height), width: crop.width / CGFloat(width), height: crop.height / CGFloat(height))
        return Subject(image: image, rect: rect)
    }
}
