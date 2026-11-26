import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramMediaResources
import FastBlur

#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif
public func chatMessageStickerResource(file: TelegramMediaFile, small: Bool) -> MediaResource {
    let resource: MediaResource
    if small, let smallest = file.previewRepresentations.first {
        resource = smallest.resource
    } else {
        resource = file.resource
    }
    return resource
}






private func customEmojiFullSizeOnly(postbox: Postbox, file: FileMediaReference, resource: MediaResource, fetched: Bool, fullSizeData: Signal<ImageRenderData, NoError>) -> Signal<ImageRenderData, NoError> {
    return Signal { subscriber in
        var fetch: Disposable?
        if fetched {
            fetch = fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: file.userLocation, userContentType: file.userContentType, reference: file.resourceReference(resource)).start()
        }
        let disposable = fullSizeData.start(next: { next in
            subscriber.putNext(next)
        }, completed: {
            subscriber.putCompletion()
        })
        return ActionDisposable {
            fetch?.dispose()
            disposable.dispose()
        }
    }
}

private func chatMessageStickerDatas(postbox: Postbox, file: FileMediaReference, small: Bool, fetched: Bool, onlyFullSize: Bool, synchronousLoad: Bool) -> Signal<ImageRenderData, NoError> {

    let thumbnailResource = chatMessageStickerResource(file: file.media, small: true)
    let resource = chatMessageStickerResource(file: file.media, small: small)

    let maybeFetched = postbox.mediaBox.cachedResourceRepresentation(resource, representation: CachedStickerAJpegRepresentation(size: small ? CGSize(width: 120.0, height: 120.0) : nil), complete: false, fetch: false, attemptSynchronously: synchronousLoad) |> runOn(synchronousLoad ? .mainQueue() : resourcesQueue)


    return maybeFetched
        |> take(1)
        |> mapToSignal { maybeData in
            if maybeData.complete {
                let loadedData: Data? = try? Data(contentsOf: URL(fileURLWithPath: maybeData.path), options: [])

                return .single(ImageRenderData(nil, loadedData, true))
            } else if file.media.isCustomEmoji {
                let fullSizeData: Signal<ImageRenderData, NoError> = postbox.mediaBox.cachedResourceRepresentation(resource, representation: CachedStickerAJpegRepresentation(size: small ? CGSize(width: 120.0, height: 120.0) : nil), complete: true)
                |> map { next in
                    return ImageRenderData(nil, !next.complete ? nil : try? Data(contentsOf: URL(fileURLWithPath: next.path), options: .mappedIfSafe), next.complete)
                }
                return customEmojiFullSizeOnly(postbox: postbox, file: file, resource: resource, fetched: fetched, fullSizeData: fullSizeData)
            } else {

                /*
                 let thumbnailData:Signal<MediaResourceData?, NoError> = .single(nil) |> then( postbox.mediaBox.cachedResourceRepresentation(thumbnailResource, representation: CachedAnimatedStickerRepresentation(thumb: true, size: size.aspectFitted(NSMakeSize(60, 60)), fitzModifier: file.media.animatedEmojiFitzModifier), complete: true) |> map(Optional.init))

                 */

                var thumbnailData:Signal<MediaResourceData?, NoError> = postbox.mediaBox.cachedResourceRepresentation(thumbnailResource, representation: CachedStickerAJpegRepresentation(size: nil), complete: true) |> map(Optional.init)
                if resource is LocalFileReferenceMediaResource {
                    thumbnailData = .single(nil)
                }
                let fullSizeData:Signal<ImageRenderData, NoError> = .single(ImageRenderData(nil, nil, false)) |> then(postbox.mediaBox.cachedResourceRepresentation(resource, representation: CachedStickerAJpegRepresentation(size: small ? CGSize(width: 120.0, height: 120.0) : nil), complete: true)
                    |> map { next in
                        return ImageRenderData(nil, !next.complete ? nil : try? Data(contentsOf: URL(fileURLWithPath: next.path), options: .mappedIfSafe), next.complete)
                })


                return Signal { subscriber in
                    var fetch: Disposable?
                    if fetched {
                        fetch = fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: file.userLocation, userContentType: file.userContentType, reference: file.resourceReference(resource)).start()
                    }

                    var fetchThumbnail: Disposable?
                    fetchThumbnail = fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: file.userLocation, userContentType: file.userContentType, reference: file.resourceReference(thumbnailResource)).start()

                    let disposable = (combineLatest(thumbnailData, fullSizeData)
                        |> map { thumbnailData, fullSizeData -> ImageRenderData in
                            if let thumbnailData = thumbnailData {
                                return ImageRenderData(thumbnailData.complete && !fullSizeData.fullSizeComplete ? try? Data(contentsOf: URL(fileURLWithPath: thumbnailData.path)) : nil, fullSizeData.fullSizeData, fullSizeData.fullSizeComplete)
                            } else {
                                return fullSizeData
                            }
                        }).start(next: { next in
                            subscriber.putNext(next)
                        }, completed: {
                            subscriber.putCompletion()
                        })

                    return ActionDisposable {
                        fetch?.dispose()
                        fetchThumbnail?.dispose()
                        disposable.dispose()
                    }
                }
            }
    }
}



public func chatMessageSticker(postbox: Postbox, file: FileMediaReference, small: Bool, scale: CGFloat, fetched: Bool = true, onlyFullSize: Bool = false, thumbnail: Bool = false, synchronousLoad: Bool = false) -> Signal<ImageDataTransformation, NoError> {
    let signal: Signal<ImageRenderData, NoError>
    signal = chatMessageStickerDatas(postbox: postbox, file: file, small: small, fetched: fetched, onlyFullSize: onlyFullSize, synchronousLoad: synchronousLoad)
    return signal |> map { data in
        return ImageDataTransformation(data: data, execute: { arguments, data in
            let context = DrawingContext(size: arguments.drawingSize, scale: scale, clear: arguments.emptyColor == nil)

            let drawingRect = arguments.drawingRect
            let fittedSize = arguments.imageSize
            let fittedRect = CGRect(origin: CGPoint(x: drawingRect.origin.x + floorToScreenPixels(scale, (drawingRect.size.width - fittedSize.width) / 2.0), y: drawingRect.origin.y + floorToScreenPixels(scale, (drawingRect.size.height - fittedSize.height) / 2.0)), size: fittedSize)
            //let fittedRect = arguments.drawingRect

            var fullSizeImage: CGImage?
            if let fullSizeData = data.fullSizeData, data.fullSizeComplete {
                if let image = NSImage(data: fullSizeData)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    fullSizeImage = image
                }
            }

            var thumbnailImage: CGImage?
            if fullSizeImage == nil, let thumbnailData = data.thumbnailData {
                if let image = NSImage(data: thumbnailData)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    thumbnailImage = image
                }
            }

            var blurredThumbnailImage: CGImage?
            let thumbnailInset: CGFloat = 10.0
            if let thumbnailImage = thumbnailImage {
                let thumbnailSize = thumbnailImage.size
                var thumbnailContextSize = thumbnailSize.aspectFitted(CGSize(width: 150.0, height: 150.0))
                let thumbnailDrawingSize = thumbnailContextSize
                thumbnailContextSize.width += thumbnailInset * 2.0
                thumbnailContextSize.height += thumbnailInset * 2.0
                let thumbnailContext = DrawingContext(size: thumbnailContextSize, scale: 1.0, clear: true)
                thumbnailContext.withFlippedContext(isHighQuality: false, horizontal: arguments.mirror, { c in
                    let cgImage = thumbnailImage
                    c.setBlendMode(.normal)
                    c.interpolationQuality = .medium
                    c.draw(cgImage, in: CGRect(origin: CGPoint(x: thumbnailInset, y: thumbnailInset), size: thumbnailDrawingSize))
                })
                stickerThumbnailAlphaBlur(Int32(thumbnailContextSize.width), Int32(thumbnailContextSize.height), Int32(thumbnailContext.bytesPerRow), thumbnailContext.bytes)

                blurredThumbnailImage = thumbnailContext.generateImage()
            }

            context.withFlippedContext(isHighQuality: data.fullSizeData != nil, horizontal: arguments.mirror, { c in
                c.clear(drawingRect)
                if let color = arguments.emptyColor {
                    c.setBlendMode(.normal)
                    switch color {
                    case let .color(color):
                        c.setFillColor(color.cgColor)
                        c.fill(drawingRect)
                    default:
                        break
                    }
                } else {
                    c.setBlendMode(.copy)
                }

                if let blurredThumbnailImage = blurredThumbnailImage {
                    c.interpolationQuality = .low
                    let thumbnailScaledInset = thumbnailInset * (fittedRect.width / blurredThumbnailImage.size.width)
                    c.draw(blurredThumbnailImage, in: fittedRect.insetBy(dx: -thumbnailScaledInset, dy: -thumbnailScaledInset))
                }

                if let fullSizeImage = fullSizeImage {
                    let cgImage = fullSizeImage
                    if case let .fill(color) = arguments.emptyColor {
                        c.clip(to: fittedRect, mask: cgImage)
                        c.setFillColor(color.cgColor)
                        c.fill(fittedRect)
                    } else {
                        c.draw(cgImage, in: fittedRect)
                    }
                }
            })

            return context
        })
    }
}






private func chatMessageAnimatedStickerDatas(postbox: Postbox, file: FileMediaReference, small: Bool, fetched: Bool, onlyFullSize: Bool, synchronousLoad: Bool, size: NSSize, thumbAtFrame: Int = 0, isVideo: Bool = false) -> Signal<ImageRenderData, NoError> {
    let thumbnailResource = chatMessageStickerResource(file: file.media, small: true)
    let resource = chatMessageStickerResource(file: file.media, small: small)

    let maybeFetched = postbox.mediaBox.cachedResourceRepresentation(resource, representation: CachedAnimatedStickerRepresentation(thumb: small, size: size, fitzModifier: file.media.animatedEmojiFitzModifier, frame: thumbAtFrame, isVideo: isVideo), complete: false, fetch: false, attemptSynchronously: synchronousLoad) |> runOn(synchronousLoad ? .mainQueue() : resourcesQueue)

    return maybeFetched
        |> take(1)
        |> mapToSignal { maybeData in
            let loadedData: Data? = try? Data(contentsOf: URL(fileURLWithPath: maybeData.path), options: [.mappedIfSafe])
            if maybeData.complete, let loadedData = loadedData, loadedData.count > 0 {
                return .single(ImageRenderData(nil, loadedData, true))
            } else if file.media.isCustomEmoji {
                let fullSizeData: Signal<ImageRenderData, NoError> = postbox.mediaBox.cachedResourceRepresentation(resource, representation: CachedAnimatedStickerRepresentation(thumb: false, size: size, fitzModifier: file.media.animatedEmojiFitzModifier, frame: thumbAtFrame, isVideo: isVideo), complete: true)
                |> map { next in
                    return ImageRenderData(nil, !next.complete ? nil : try? Data(contentsOf: URL(fileURLWithPath: next.path), options: .mappedIfSafe), next.complete)
                }
                return customEmojiFullSizeOnly(postbox: postbox, file: file, resource: resource, fetched: fetched, fullSizeData: fullSizeData)
            } else {
                let thumbnailData:Signal<MediaResourceData?, NoError> =  postbox.mediaBox.cachedResourceRepresentation(thumbnailResource, representation: CachedAnimatedStickerRepresentation(thumb: true, size: size.aspectFitted(NSMakeSize(60, 60)), fitzModifier: file.media.animatedEmojiFitzModifier, frame: thumbAtFrame, isVideo: false), complete: true) |> map(Optional.init)


                let fullSizeData:Signal<ImageRenderData, NoError> = .single(ImageRenderData(nil, nil, false)) |> then(postbox.mediaBox.cachedResourceRepresentation(resource, representation: CachedAnimatedStickerRepresentation(thumb: false, size: size, fitzModifier: file.media.animatedEmojiFitzModifier, frame: thumbAtFrame, isVideo: isVideo), complete: true)
                     |> map { next in
                         return ImageRenderData(nil, !next.complete ? nil : try? Data(contentsOf: URL(fileURLWithPath: next.path), options: .mappedIfSafe), next.complete)
                     })

                return Signal { subscriber in
                    var fetch: Disposable?
                    if fetched {
                        fetch = fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: file.userLocation, userContentType: file.userContentType, reference: file.resourceReference(resource)).start()
                    }

                    var fetchThumbnail: Disposable?
                    fetchThumbnail = fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: file.userLocation, userContentType: file.userContentType, reference: file.resourceReference(thumbnailResource)).start()

                    let disposable = (combineLatest(thumbnailData, fullSizeData)
                        |> map { thumbnailData, fullSizeData -> ImageRenderData in
                            if let thumbnailData = thumbnailData {
                                return ImageRenderData(thumbnailData.complete && !fullSizeData.fullSizeComplete ? try? Data(contentsOf: URL(fileURLWithPath: thumbnailData.path)) : nil, fullSizeData.fullSizeData, fullSizeData.fullSizeComplete)
                            } else {
                                return ImageRenderData(nil, fullSizeData.fullSizeData, fullSizeData.fullSizeComplete)
                            }
                        }).start(next: { next in
                            subscriber.putNext(next)
                        }, completed: {
                            subscriber.putCompletion()
                        })

                    return ActionDisposable {
                        fetch?.dispose()
                        fetchThumbnail?.dispose()
                        disposable.dispose()
                    }
                }
            }
    }
}





public func chatMessageAnimatedSticker(postbox: Postbox, file: FileMediaReference, small: Bool, scale: CGFloat, size: NSSize, fetched: Bool = false, onlyFullSize: Bool = false, synchronousLoad: Bool = false, thumbAtFrame: Int = 0, isVideo: Bool) -> Signal<ImageDataTransformation, NoError> {
    let signal: Signal<ImageRenderData, NoError> = chatMessageAnimatedStickerDatas(postbox: postbox, file: file, small: small, fetched: fetched, onlyFullSize: onlyFullSize, synchronousLoad: synchronousLoad, size: size, thumbAtFrame: thumbAtFrame, isVideo: isVideo)
    return signal |> map { data in
        return ImageDataTransformation(data: data, execute: { arguments, data in
            let context = DrawingContext(size: arguments.drawingSize, scale: scale, clear: arguments.emptyColor == nil)

            let drawingRect = arguments.drawingRect
            let fittedSize = arguments.imageSize
            let fittedRect = CGRect(origin: CGPoint(x: drawingRect.origin.x + floorToScreenPixels(scale, floorToScreenPixels(scale, (drawingRect.size.width - fittedSize.width) / 2.0)), y: drawingRect.origin.y + floorToScreenPixels(scale, floorToScreenPixels(scale, (drawingRect.size.height - fittedSize.height) / 2.0))), size: fittedSize)
            //let fittedRect = arguments.drawingRect

            var fullSizeImage: CGImage?
            if let fullSizeData = data.fullSizeData, data.fullSizeComplete {
                if let image = NSImage(data: fullSizeData)?._cgImage {
                    fullSizeImage = image
                }
            }

            var thumbnailImage: CGImage?
            if fullSizeImage == nil, let thumbnailData = data.thumbnailData {
                if let image = NSImage(data: thumbnailData)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    thumbnailImage = image
                }
            }

            var blurredThumbnailImage: CGImage?
            let thumbnailInset: CGFloat = 10.0
            if let thumbnailImage = thumbnailImage {
                let thumbnailSize = thumbnailImage.size
                var thumbnailContextSize = thumbnailSize.aspectFitted(CGSize(width: 150.0, height: 150.0))
                let thumbnailDrawingSize = thumbnailContextSize
                thumbnailContextSize.width += thumbnailInset * 2.0
                thumbnailContextSize.height += thumbnailInset * 2.0
                let thumbnailContext = DrawingContext(size: thumbnailContextSize, scale: 1.0, clear: true)
                thumbnailContext.withFlippedContext(isHighQuality: false, horizontal: arguments.mirror, { c in
                    let cgImage = thumbnailImage
                    c.setBlendMode(.normal)
                    c.interpolationQuality = .medium

                    c.draw(cgImage, in: CGRect(origin: CGPoint(x: thumbnailInset, y: thumbnailInset), size: thumbnailDrawingSize))
                })
                stickerThumbnailAlphaBlur(Int32(thumbnailContextSize.width), Int32(thumbnailContextSize.height), Int32(thumbnailContext.bytesPerRow), thumbnailContext.bytes)

                blurredThumbnailImage = thumbnailContext.generateImage()
            }
            context.withFlippedContext(isHighQuality: data.fullSizeData != nil, horizontal: arguments.mirror, { c in
                c.clear(drawingRect)
                if let color = arguments.emptyColor {
                    c.setBlendMode(.normal)
                    switch color {
                    case let .color(color):
                        c.setFillColor(color.cgColor)
                        c.fill(drawingRect)
                    default:
                        break
                    }
                } else {
                    c.setBlendMode(.copy)
                }

                if let blurredThumbnailImage = blurredThumbnailImage, fullSizeImage == nil {
                    c.interpolationQuality = .low
                    let thumbnailScaledInset = thumbnailInset * (fittedRect.width / blurredThumbnailImage.size.width)
                    let rect = fittedRect.insetBy(dx: -thumbnailScaledInset, dy: -thumbnailScaledInset)
                    if case let .fill(color) = arguments.emptyColor {
                        c.clip(to: rect, mask: blurredThumbnailImage)
                        c.setFillColor(color.cgColor)
                        c.fill(rect)
                    } else {
                        c.draw(blurredThumbnailImage, in: rect)
                    }
                }

                if let fullSizeImage = fullSizeImage {
                    let cgImage = fullSizeImage
                    c.setBlendMode(.normal)
                    c.interpolationQuality = .medium
                    if case let .fill(color) = arguments.emptyColor {
                        c.clip(to: fittedRect, mask: cgImage)
                        c.setFillColor(color.cgColor)
                        c.fill(fittedRect)
                    } else {
                        c.draw(cgImage, in: fittedRect)
                    }

                   // c.setFillColor(NSColor.random.cgColor)
                   // c.fill(fittedRect)
                }
            })

            return context
        })
    }
}
