import Cocoa
import FastBlur
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramMediaResources

#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#if SHARE
import InlineStickersShare
#else
import InlineStickers
#endif
#endif
public let graphicsThreadPool = ThreadPool(threadCount: 5, threadPriority: 1)

public enum PeerPhoto {
    case peer(Peer, TelegramMediaImageRepresentation?, PeerNameColor?, [String], Message?, CGFloat?)
    case topic(EngineMessageHistoryThread.Info, Bool)
}

private let capHolder:Atomic<[String : CGImage]> = Atomic(value: [:])

private func peerImage(account: Account, peer: Peer, displayDimensions: NSSize, representation: TelegramMediaImageRepresentation?, message: Message? = nil, displayLetters: [String], font: NSFont, scale: CGFloat, genCap: Bool, synchronousLoad: Bool, disableForum: Bool = false, cornerRadius: CGFloat? = nil, forceForum: Bool = false) -> Signal<(CGImage?, Bool), NoError> {

    let isForum: Bool = ((peer.isForumOrMonoForum || (peer is TelegramCommunity)) || forceForum) && !disableForum
    let isMonoforum: Bool = peer.isMonoForum
    let forcedCommunityCornerRadius: CGFloat = floor(min(displayDimensions.width, displayDimensions.height) * 0.176)

    if isMonoforum {
        var bp = 0
        bp += 1
    }

    if let representation = representation {
        return cachedPeerPhoto(peer.id, representation: representation, peerNameColor: nil, size: displayDimensions, scale: scale, isForum: isForum, isMonoforum: isMonoforum) |> mapToSignal { cached -> Signal<(CGImage?, Bool), NoError> in
            return autoreleasepool {
                if let cached = cached {
                    return .single((cached, false))
                } else {
                    let resourceData = account.postbox.mediaBox.resourceData(representation.resource, attemptSynchronously: synchronousLoad)
                    let imageData = resourceData
                        |> take(1)
                        |> mapToSignal { maybeData -> Signal<(Data?, Bool, Bool), NoError> in
                            return autoreleasepool {
                               if maybeData.complete {
                                   return .single((try? Data(contentsOf: URL(fileURLWithPath: maybeData.path)), false, false))
                               } else {
                                   return Signal { subscriber in

                                       if let data = representation.immediateThumbnailData {
                                           subscriber.putNext((decodeTinyThumbnail(data: data), false, true))
                                       }

                                       let resourceData = account.postbox.mediaBox.resourceData(representation.resource, attemptSynchronously: synchronousLoad)

                                       let resourceDataDisposable = resourceData.start(next: { data in
                                           if data.complete {
                                               subscriber.putNext((try? Data(contentsOf: URL(fileURLWithPath: data.path)), true, false))
                                               subscriber.putCompletion()
                                           }
                                       }, completed: {
                                           subscriber.putCompletion()
                                       })

                                       let fetchedDataDisposable: Disposable
                                       if let message = message, message.author?.id == peer.id {
                                           fetchedDataDisposable = fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .peer(peer.id), userContentType: .avatar, reference: MediaResourceReference.messageAuthorAvatar(message: MessageReference(message), resource: representation.resource), statsCategory: .image).start()
                                        } else if let reference = PeerReference(peer) {
                                            fetchedDataDisposable = fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .peer(peer.id), userContentType: .avatar, reference: MediaResourceReference.avatar(peer: reference, resource: representation.resource), statsCategory: .image).start()
                                       } else {
                                           fetchedDataDisposable = fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .peer(peer.id), userContentType: .avatar, reference: MediaResourceReference.standalone(resource: representation.resource), statsCategory: .image).start()
                                       }
                                       return ActionDisposable {
                                           resourceDataDisposable.dispose()
                                           fetchedDataDisposable.dispose()
                                       }
                                   }
                               }
                            }
                    }

                    let def = deferred({ () -> Signal<(CGImage?, Bool), NoError> in
                        let key = NSStringFromSize(displayDimensions)
                        if let image = capHolder.with({ $0[key] }) {
                            return .single((image, false))
                        } else {
                            let size = NSMakeSize(max(15, displayDimensions.width), max(15, displayDimensions.height))
                            let image = generateAvatarPlaceholder(foregroundColor: theme.colors.grayBackground, size: size, cornerRadius: isForum ? floor(size.height / 4) : (cornerRadius ?? -1), bubble: isMonoforum)
                            _ = capHolder.modify { current in
                                var current = current
                                current[key] = image
                                return current
                            }
                            return .single((image, false))
                        }
                    }) |> deliverOnMainQueue

                    let loadDataSignal = synchronousLoad ? imageData : imageData |> deliverOn(graphicsThreadPool)

                    let img = loadDataSignal |> mapToSignal { data, animated, tiny -> Signal<(CGImage?, Bool), NoError> in

                        var image:CGImage?
                        if let data = data {
                            image = roundImage(data, displayDimensions, cornerRadius: forceForum ? forcedCommunityCornerRadius : (isForum ? displayDimensions.width / 4 : (cornerRadius ?? -1)), scale: scale, bubble: isMonoforum)
                        } else {
                            image = nil
                        }
                        #if !SHARE
                        if tiny, let img = image {
                            let size = img.size
                            let ctx = DrawingContext(size: img.size, scale: 1.0)
                            ctx.withContext { ctx in
                                ctx.clear(size.bounds)
                                ctx.draw(img, in: size.bounds)
                            }
                            telegramFastBlurMore(Int32(size.width), Int32(size.height), Int32(ctx.bytesPerRow), ctx.bytes)

                            let rounded = DrawingContext(size: img.size, scale: 1.0)
                            rounded.withContext { c in
                                c.clear(size.bounds)
                                c.round(size, isForum ? min(floor(size.height / 4), size.height / 2) : size.height / 2)
                                c.clear(size.bounds)
                                c.draw(ctx.generateImage()!, in: size.bounds)
                            }

                            image = rounded.generateDisplayImage()
                        }
                        #endif
                        image = image.flatMap(makeDisplayImage)
                        if let image = image {
                            if tiny {
                                return .single((image, animated))
                            }
                            return cachePeerPhoto(image: image, peerId: peer.id, representation: representation, peerNameColor: nil, size: displayDimensions, scale: scale, isForum: isForum, isMonoforum: isMonoforum) |> map {
                                return (image, animated)
                            }
                        } else {
                            return .single((image, animated))
                        }

                    }
                    if genCap {
                        return def |> then(img)
                    } else {
                        return img
                    }
                }
            }
        }

    } else {

        var letters = displayLetters
        if letters.count < 2 {
            while letters.count != 2 {
                letters.append("")
            }
        }

        //peer.nameColor?.index ??
        let number = peer.id.id._internalGetInt64Value()
        let index = Int(abs(number % 7))
        let color = theme.colors.peerColors(index)


        let symbol = letters.reduce("", { (current, letter) -> String in
            return current + letter
        })

        return cachedEmptyPeerPhoto(peer.id, symbol: symbol, color: color.top, size: displayDimensions, scale: scale, isForum: isForum, isMonoforum: isMonoforum) |> mapToSignal { cached -> Signal<(CGImage?, Bool), NoError> in
            if let cached = cached {
                return .single((cached, false))
            } else {
                let emptyPhoto = generateEmptyPhoto(displayDimensions, type: .peer(colors: color, letter: letters, font: font, cornerRadius: forceForum ? forcedCommunityCornerRadius : (isForum ? floor(displayDimensions.height / 3) : nil)), bubble: isMonoforum)
                return (synchronousLoad ? emptyPhoto : emptyPhoto |> runOn(graphicsThreadPool)) |> mapToSignal { image -> Signal<(CGImage?, Bool), NoError> in
                    if let image = image {
                        return cacheEmptyPeerPhoto(image: image, peerId: peer.id, symbol: symbol, color: color.top, size: displayDimensions, scale: scale, isForum: isForum, isMonoforum: isMonoforum) |> map {
                            return (image, false)
                        }
                    } else {
                        return .single((image, false))
                    }
                }
            }
        }

    }
}

public func peerAvatarImage(account: Account, photo: PeerPhoto, displayDimensions: CGSize = CGSize(width: 60.0, height: 60.0), scale:CGFloat = 1.0, font:NSFont = .medium(17), genCap: Bool = true, synchronousLoad: Bool = false, disableForum: Bool = false, forceForum: Bool = false) -> Signal<(CGImage?, Bool), NoError> {

    switch photo {
    case let .peer(peer, representation, _, displayLetters, message, cornerRadius):
        return peerImage(account: account, peer: peer, displayDimensions: displayDimensions, representation: representation, message: message, displayLetters: displayLetters, font: font, scale: scale, genCap: genCap, synchronousLoad: synchronousLoad, disableForum: disableForum, cornerRadius: cornerRadius, forceForum: forceForum)
    case let .topic(info, isGeneral):
        #if !SHARE

        let file: Signal<TelegramMediaFile, NoError>

        if let fileId = info.icon {
            file = TelegramEngine(account: account).stickers.resolveInlineStickers(fileIds: [fileId]) |> map {
                return $0[fileId]
            }
            |> filter { $0 != nil }
            |> map { $0! }
        } else {
            file = .single(TelegramUtilsHooks.shared.topicFile!(info.title, info.iconColor, isGeneral))
        }

        return file |> mapToSignal { file in
            let reference = FileMediaReference.standalone(media: file)
            let signal:Signal<ImageDataTransformation, NoError>

            let emptyColor: TransformImageEmptyColor?
            if isDefaultStatusesPackId(file.emojiReference) {
                emptyColor = .fill(theme.colors.accent)
            } else {
                emptyColor = nil
            }

            let aspectSize = file.dimensions?.size.aspectFilled(displayDimensions) ?? displayDimensions
            let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: aspectSize, boundingSize: displayDimensions, intrinsicInsets: NSEdgeInsets(), emptyColor: emptyColor)

            switch file.mimeType {
            case "image/webp":
                signal = chatMessageSticker(postbox: account.postbox, file: reference, small: false, scale: System.backingScale, fetched: true)
            case "bundle/topic":
                if let resource = file.resource as? ForumTopicIconResource {
                    signal = TelegramUtilsHooks.shared.topicImage!(resource.title, resource.bgColors, resource.strokeColors)
                } else {
                    signal = .complete()
                }
            case "bundle/jpeg":
                if let resource = file.resource as? LocalBundleResource {
                    signal = TelegramUtilsHooks.shared.generalTopicImage!(resource, System.backingScale)
                } else {
                    signal = .complete()
                }
            default:
                signal = chatMessageAnimatedSticker(postbox: account.postbox, file: reference, small: false, scale: System.backingScale, size: aspectSize, fetched: true, thumbAtFrame: 0, isVideo: file.fileName == "webm-preview" || file.isVideoSticker)
            }
            return signal |> map { data -> (CGImage?, Bool) in
                let context = data.execute(arguments, data.data)
                let image = context?.generateDisplayImage()
                return (image, true)
            }
        }
        #else
        return .complete()
        #endif
    }
}

/*

 */





public func generateEmptyRoundAvatar(_ displayDimensions:NSSize, font: NSFont, account:Account, peer:Peer) -> Signal<CGImage?, NoError> {
    return Signal { subscriber in
        let letters = TelegramUtilsHooks.shared.peerLetters(peer)

        //peer.nameColor?.index ??
        let number = peer.id.id._internalGetInt64Value()
        let index = Int(abs(number % 7))

        let color = theme.colors.peerColors(index)

        let image = generateImage(displayDimensions, contextGenerator: { (size, ctx) in
            ctx.clear(NSMakeRect(0, 0, size.width, size.height))

            var locations: [CGFloat] = [1.0, 0.2];
            let colorSpace = deviceColorSpace
            let gradient = CGGradient(colorsSpace: colorSpace, colors: NSArray(array: [color.top.cgColor, color.bottom.cgColor]), locations: &locations)!

            ctx.drawLinearGradient(gradient, start: CGPoint(), end: CGPoint(x: 0.0, y: size.height), options: CGGradientDrawingOptions())

            ctx.setBlendMode(.normal)

            let letters = letters
            let string = letters.count == 0 ? "" : (letters[0] + (letters.count == 1 ? "" : letters[1]))
            let attributedString = NSAttributedString(string: string, attributes: [NSAttributedString.Key.font: font, NSAttributedString.Key.foregroundColor: NSColor.white])

            let line = CTLineCreateWithAttributedString(attributedString)
            let lineBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

            let lineOrigin = CGPoint(x: floorToScreenPixels(System.backingScale, -lineBounds.origin.x + (size.width - lineBounds.size.width) / 2.0) , y: floorToScreenPixels(System.backingScale, -lineBounds.origin.y + (size.height - lineBounds.size.height) / 2.0))

            ctx.translateBy(x: size.width / 2.0, y: size.height / 2.0)
            ctx.scaleBy(x: 1.0, y: 1.0)
            ctx.translateBy(x: -size.width / 2.0, y: -size.height / 2.0)
            //
            ctx.translateBy(x: lineOrigin.x, y: lineOrigin.y)
            CTLineDraw(line, ctx)
            ctx.translateBy(x: -lineOrigin.x, y: -lineOrigin.y)
        })
        subscriber.putNext(image)
        subscriber.putCompletion()
        return EmptyDisposable
    }


}
public func generateAvatarPlaceholder(foregroundColor: NSColor, size: NSSize, cornerRadius: CGFloat = -1, bubble: Bool = false) -> CGImage {
    return generateImage(size, contextGenerator: { size, ctx in
        ctx.clear(NSMakeRect(0, 0, size.width, size.height))
        if bubble {
            let rect = CGRect(origin: CGPoint(), size: size)
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.scaleBy(x: 1.0, y: -1.0)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
            addAvatarBubblePath(context: ctx, rect: rect)
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.scaleBy(x: 1.0, y: -1.0)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
            ctx.clip()
        } else {
            if cornerRadius == -1 {
                ctx.round(size, size.width/2)
            } else {
                ctx.round(size, min(cornerRadius, size.width / 2))
            }
        }

        ctx.setFillColor(foregroundColor.cgColor)
        ctx.fill(NSMakeRect(0, 0, size.width, size.height))
    })!
}
