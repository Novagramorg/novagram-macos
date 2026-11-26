import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import TelegramContext

func qrStudioCrossfadeContents(_ layer: CALayer) {
    let transition = CATransition()
    transition.type = .fade
    transition.duration = 0.25
    transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(transition, forKey: "contents")
}

func qrStudioTintKey(_ color: NSColor?) -> String {
    guard let color = color?.usingColorSpace(.sRGB) else {
        return "none"
    }
    return String(format: "%.4f-%.4f-%.4f-%.4f", Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent), Double(color.alphaComponent))
}

func qrStudioFirstFrameImage(context: any AccountContextProtocol, file: TelegramMediaFile, pointSize: CGSize, completion: @escaping (CGImage?) -> Void) -> Disposable {
    let pixelSide = Int(floor(max(pointSize.width, pointSize.height) * System.backingScale))
    return (qrStudioDecodeExportSticker(context: context, file: file, pixelSide: pixelSide, tint: nil, firstFrameOnly: true)
    |> deliverOnMainQueue).start(next: { sticker in
        completion(sticker?.frames.first)
    })
}

private final class QrStudioWeakFrames {
    weak var value: QrStudioExportSticker?

    init(_ value: QrStudioExportSticker) {
        self.value = value
    }
}

private var qrStudioPhasedFrames: [String: QrStudioWeakFrames] = [:]

private let qrStudioPhasedEpoch = CACurrentMediaTime()

private final class QrStudioPhaseMember {
    weak var layer: CALayer?
    let group: Int

    init(layer: CALayer, group: Int) {
        self.layer = layer
        self.group = group
    }
}

final class QrStudioPhasedAnimation {
    static let groupCount = 6
    private static let animationKey = "qrPhasedFrames"

    let file: TelegramMediaFile
    let tintKey: String
    private let pixelSide: Int
    private var members: [ObjectIdentifier: QrStudioPhaseMember] = [:]
    private var firstFrameDisposable: Disposable?
    private var framesDisposable: Disposable?
    private var placeholder: CGImage?
    private var firstFrame: CGImage?
    private var frames: QrStudioExportSticker?
    private var isPaused = false

    private(set) var hasFrames = false
    var hasPlaceholder: Bool {
        return self.placeholder != nil || self.firstFrame != nil
    }
    var onFirstFrame: (() -> Void)?

    init(context: any AccountContextProtocol, file: TelegramMediaFile, pointSize: CGSize, tint: NSColor? = nil, placeholderColor: NSColor? = nil) {
        self.file = file
        self.tintKey = qrStudioTintKey(tint)
        self.pixelSide = Int(floor(max(pointSize.width, pointSize.height) * System.backingScale))

        if let placeholderColor = placeholderColor, let data = file.immediateThumbnailData {
            let imageSize: CGSize
            if let dimensions = file.dimensions {
                imageSize = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
            } else {
                imageSize = CGSize(width: 512.0, height: 512.0)
            }
            self.placeholder = generateStickerPlaceholderImage(data: data, size: pointSize, scale: min(2.0, System.backingScale), imageSize: imageSize, backgroundColor: nil, foregroundColor: placeholderColor)
        }

        let framesKey = "\(file.fileId.id)-\(self.pixelSide)-\(self.tintKey)"
        if let frames = qrStudioPhasedFrames[framesKey]?.value {
            self.frames = frames
            self.hasFrames = true
            return
        }

        self.firstFrameDisposable = (qrStudioDecodeExportSticker(context: context, file: file, pixelSide: self.pixelSide, tint: tint, firstFrameOnly: true)
        |> deliverOnMainQueue).start(next: { [weak self] result in
            guard let self, self.frames == nil, let image = result?.frames.first else {
                return
            }
            self.firstFrame = image
            for member in self.members.values {
                member.layer?.contents = image
            }
        })

        self.framesDisposable = (qrStudioDecodeExportSticker(context: context, file: file, pixelSide: self.pixelSide, tint: tint, firstFrameOnly: false)
        |> deliverOnMainQueue).start(next: { [weak self] frames in
            guard let self = self, let frames = frames else {
                return
            }
            qrStudioPhasedFrames[framesKey] = QrStudioWeakFrames(frames)
            self.frames = frames
            let startsFromFirstFrame = self.firstFrame != nil
            for (_, member) in self.members {
                if let layer = member.layer {
                    if !startsFromFirstFrame {
                        qrStudioCrossfadeContents(layer)
                    }
                    self.apply(layer, group: member.group, startsFromFirstFrame: startsFromFirstFrame)
                }
            }
            self.firstFrame = nil
            self.firstFrameDisposable?.dispose()
            if !self.hasFrames {
                self.hasFrames = true
                self.onFirstFrame?()
            }
        })
    }

    deinit {
        self.firstFrameDisposable?.dispose()
        self.framesDisposable?.dispose()
    }

    func setPaused(_ isPaused: Bool) {
        guard self.isPaused != isPaused else {
            return
        }
        self.isPaused = isPaused
        for (_, member) in self.members {
            if let layer = member.layer {
                self.apply(layer, group: member.group)
            }
        }
    }

    private func apply(_ layer: CALayer, group: Int, startsFromFirstFrame: Bool = false) {
        guard let frames = self.frames, !frames.frames.isEmpty else {
            layer.contents = self.firstFrame ?? self.placeholder
            return
        }
        let offset = frames.period * Double(group) / Double(QrStudioPhasedAnimation.groupCount)
        layer.removeAnimation(forKey: QrStudioPhasedAnimation.animationKey)
        if frames.isAnimated {
            let elapsed = CACurrentMediaTime() - qrStudioPhasedEpoch + offset
            let local = elapsed.truncatingRemainder(dividingBy: frames.period)
            let index = min(frames.frames.count - 1, max(0, Int(Double(frames.frames.count) * local / frames.period)))
            layer.contents = frames.frames[index]
            guard !self.isPaused else {
                return
            }
            let animation = CAKeyframeAnimation(keyPath: "contents")
            animation.values = frames.frames
            animation.duration = frames.period
            animation.calculationMode = .discrete
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            if startsFromFirstFrame {
                layer.contents = frames.frames[0]
                let start = qrStudioPhasedEpoch - offset + ceil(elapsed / frames.period) * frames.period
                animation.beginTime = layer.convertTime(start, from: nil)
            } else {
                animation.timeOffset = offset
                animation.beginTime = layer.convertTime(qrStudioPhasedEpoch, from: nil)
            }
            layer.add(animation, forKey: QrStudioPhasedAnimation.animationKey)
        } else {
            layer.contents = frames.frames.first
        }
    }

    func attach(_ layer: CALayer, group: Int) {
        let key = ObjectIdentifier(layer)
        if let current = self.members[key], current.layer === layer, current.group == group {
            return
        }
        self.members[key] = QrStudioPhaseMember(layer: layer, group: group)
        self.apply(layer, group: group)
    }

    func detach(_ layer: CALayer) {
        guard self.members.removeValue(forKey: ObjectIdentifier(layer)) != nil else {
            return
        }
        layer.removeAnimation(forKey: QrStudioPhasedAnimation.animationKey)
    }
}
