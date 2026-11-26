import Cocoa
import TelegramCore
import InAppSettings
import ColorPalette
import TGUIKit
import SwiftSignalKit
import Postbox
import ThemeSettings
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import TelegramIconsTheme
import FoundationUtils
import TelegramMediaUtils
import TelegramLinks
import ChatHistoryModel
import FilePanels
import WallpaperUI

private func cloudThemeData(context: any AccountContextProtocol, theme: TelegramTheme, file: TelegramMediaFile) -> Signal<(ColorPalette, Wallpaper, TelegramWallpaper?), NoError> {
    return Signal { subscriber in
        
        let fetchDisposable = fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.theme(theme: ThemeReference.slug(theme.slug), resource: file.resource)).start()
        let wallpaperDisposable = DisposableSet()
        
        let resourceData = context.account.postbox.mediaBox.resourceData(file.resource) |> filter { $0.complete } |> take(1)
        
        let dataDisposable = resourceData.start(next: { data in
            if let palette = importPalette(data.path) {
                var wallpaper: Signal<TelegramWallpaper?, GetWallpaperError> = .single(nil)
                var newSettings: WallpaperSettings = WallpaperSettings()
                switch palette.wallpaper {
                case .none:
                    wallpaper = .single(nil)
                case .builtin:
                    wallpaper = .single(.builtin(newSettings))
                case let .color(color):
                    wallpaper = .single(.color(color.argb))
                case let .url(string):
                    let link = SettingsHooks.shared.inAppLink(string as NSString, context)
                    switch link {
                    case let .wallpaper(_, _, preview):
                        switch preview {
                        case let .slug(slug, settings):
                            wallpaper = getWallpaper(network: context.account.network, slug: slug) |> map(Optional.init)
                            newSettings = settings
                        default:
                            break
                        }
                    default:
                        break
                    }
                }
                
                wallpaperDisposable.add(wallpaper.start(next: { cloud in
                    if let cloud = cloud {
                        let wp = Wallpaper(cloud).withUpdatedSettings(newSettings)
                        wallpaperDisposable.add(moveWallpaperToCache(postbox: context.account.postbox, wallpaper: wp).start(next: { wallpaper in
                            subscriber.putNext((palette, wallpaper, cloud))
                            subscriber.putCompletion()
                        }))
                    } else {
                        subscriber.putNext((palette, .none, nil))
                        subscriber.putCompletion()
                    }
                }, error: { _ in
                    subscriber.putCompletion()
                }))
            }
            
        })

        return ActionDisposable {
            fetchDisposable.dispose()
            dataDisposable.dispose()
            wallpaperDisposable.dispose()
        }
    }
}



private func generateThumb(palette: ColorPalette, bubbled: Bool, wallpaper: Wallpaper, emoticonThemes: [(ChatTheme, TelegramPresentationTheme)]) -> Signal<CGImage, NoError> {
    return Signal { subscriber in
        let image = generateImage(NSMakeSize(80, 55), rotatedContext: { size, ctx in
            let rect = NSMakeRect(0, 0, size.width, size.height)
            ctx.clear(rect)
            ctx.round(size, 10)
            
            
            let backgroundMode: TableBackgroundMode
            if bubbled {
                switch wallpaper {
                case .builtin:
                    backgroundMode = TelegramPresentationTheme.defaultBackground(palette)
                case let.color(color):
                    backgroundMode = .color(color: NSColor(argb: color).withAlphaComponent(1.0))
                case let .gradient(_, colors, rotation):
                    backgroundMode = .gradient(colors: colors.map { NSColor(argb: $0).withAlphaComponent(1.0) }, rotation: rotation)
                case let .image(representation, settings):
                    if let resource = largestImageRepresentation(representation)?.resource, let image = downsampledImage(contentsOfFile: wallpaperPath(resource, settings: settings), maxPixelSize: max(size.width, size.height) * System.backingScale) {
                        backgroundMode = .background(image: image, intensity: settings.intensity, colors: settings.colors.map { NSColor(argb: $0) }, rotation: settings.rotation, metadata: nil)
                    } else {
                        backgroundMode = TelegramPresentationTheme.defaultBackground(palette)
                    }
                    
                case let .file(_, file, settings, _, _):
                    if let image = downsampledImage(contentsOfFile: wallpaperPath(file.resource, settings: settings), maxPixelSize: max(size.width, size.height) * System.backingScale) {
                        backgroundMode = .background(image: image, intensity: settings.intensity, colors: settings.colors.map { NSColor(argb: $0) }, rotation: settings.rotation, metadata: nil)
                    } else {
                        backgroundMode = TelegramPresentationTheme.defaultBackground(palette)
                    }
                case .none:
                    backgroundMode = .color(color: palette.chatBackground)
                case let .custom(representation, blurred):
                    if let image = downsampledImage(contentsOfFile: wallpaperPath(representation.resource, settings: WallpaperSettings(blur: blurred)), maxPixelSize: max(size.width, size.height) * System.backingScale) {
                        backgroundMode = .background(image: image, intensity: nil, colors: nil, rotation: nil, metadata: nil)
                    } else {
                        backgroundMode = TelegramPresentationTheme.defaultBackground(palette)
                    }
                case let .emoticon(emoticon):
                    if let first = emoticonThemes.first(where: { $0.0.id == emoticon.strippedEmoji }) {
                        backgroundMode = first.1.backgroundMode
                    } else {
                        backgroundMode = .plain
                    }
                }
            } else {
                backgroundMode = .color(color: palette.chatBackground)
            }
            
            func applyBubbles() {
                let bubbleImage = TelegramThemeHooks.shared.image(.iconThemeBubble)
                let incoming = bubbleImage.precomposed(palette.bubbleBackground_incoming, flipVertical: true)
                ctx.draw(incoming, in: NSMakeRect(7, 9, 48, 16))
                let outgoing = bubbleImage.precomposed(palette.bubbleBackground_outgoing, flipVertical: true, flipHorizontal: true)
                ctx.draw(outgoing, in: NSMakeRect(size.width - 57, size.height - 24, 48, 16))
            }
            
            func applyPlain() {
                ctx.setFillColor(palette.accent.cgColor)
                ctx.fillEllipse(in: NSMakeRect(10, 7, 17, 17))
                
                if true {
                    let name1 = generateImage(NSMakeSize(20, 4), rotatedContext: { size, ctx in
                        let rect = NSMakeRect(0, 0, size.width, size.height)
                        ctx.clear(rect)
                        ctx.round(size, 2)
                        ctx.setFillColor(palette.accent.cgColor)
                        ctx.fill(rect)
                    })!
                    ctx.draw(name1, in: NSMakeRect(10 + 17 + 3, 7 + 2, name1.backingSize.width, name1.backingSize.height))
                    
                    let text1 = generateImage(NSMakeSize(40, 4), rotatedContext: { size, ctx in
                        let rect = NSMakeRect(0, 0, size.width, size.height)
                        ctx.clear(rect)
                        ctx.round(size, 2)
                        ctx.setFillColor(palette.grayText.withAlphaComponent(0.5).cgColor)
                        ctx.fill(rect)
                    })!
                    ctx.draw(text1, in: NSMakeRect(10 + 17 + 3, 7 + 2 + 4 + 4, text1.backingSize.width, text1.backingSize.height))
                }
                
                if true {
                    ctx.setFillColor(palette.accent.cgColor)
                    ctx.fillEllipse(in: NSMakeRect(10, 7 + 17 + 7, 17, 17))
                    
                    let name1 = generateImage(NSMakeSize(20, 4), rotatedContext: { size, ctx in
                        let rect = NSMakeRect(0, 0, size.width, size.height)
                        ctx.clear(rect)
                        ctx.round(size, 2)
                        ctx.setFillColor(palette.accent.cgColor)
                        ctx.fill(rect)
                    })!
                    ctx.draw(name1, in: NSMakeRect(10 + 17 + 3, 7 + 17 + 7 + 2, name1.backingSize.width, name1.backingSize.height))
                    
                    let text1 = generateImage(NSMakeSize(40, 4), rotatedContext: { size, ctx in
                        let rect = NSMakeRect(0, 0, size.width, size.height)
                        ctx.clear(rect)
                        ctx.round(size, 2)
                        ctx.setFillColor(palette.grayText.withAlphaComponent(0.5).cgColor)
                        ctx.fill(rect)
                    })!
                    ctx.draw(text1, in: NSMakeRect(10 + 17 + 3, 7 + 17 + 7 + 2 + 4 + 4, text1.backingSize.width, text1.backingSize.height))
                }
                
                
            }
            drawBg(backgroundMode, palette: palette, bubbled: bubbled, rect: rect, in: ctx)
            if bubbled {
                applyBubbles()
            } else {
                applyPlain()
            }
            
        })!
        
        subscriber.putNext(image)
        subscriber.putCompletion()
        
        return EmptyDisposable
    } |> runOn(Queue.concurrentDefaultQueue())
}


private func generateWidgetThumb(palette: ColorPalette, bubbled: Bool, wallpaper: Wallpaper, emoticonThemes: [(ChatTheme, TelegramPresentationTheme)]) -> Signal<CGImage, NoError> {
    return Signal { subscriber in
        let image = generateImage(NSMakeSize(132, 86), rotatedContext: { size, ctx in
            let rect = NSMakeRect(0, 0, size.width, size.height)
            ctx.clear(rect)
            ctx.round(size, 17)
            
            
            let backgroundMode: TableBackgroundMode
            if bubbled {
                switch wallpaper {
                case .builtin:
                    backgroundMode = TelegramPresentationTheme.defaultBackground(palette)
                case let.color(color):
                    backgroundMode = .color(color: NSColor(argb: color).withAlphaComponent(1.0))
                case let .gradient(_, colors, rotation):
                    backgroundMode = .gradient(colors: colors.map { NSColor(argb: $0).withAlphaComponent(1.0) }, rotation: rotation)
                case let .image(representation, settings):
                    if let resource = largestImageRepresentation(representation)?.resource, let image = downsampledImage(contentsOfFile: wallpaperPath(resource, settings: settings), maxPixelSize: max(size.width, size.height) * System.backingScale) {
                        backgroundMode = .background(image: image, intensity: settings.intensity, colors: settings.colors.map { NSColor(argb: $0) }, rotation: settings.rotation, metadata: nil)
                    } else {
                        backgroundMode = TelegramPresentationTheme.defaultBackground(palette)
                    }
                    
                case let .file(_, file, settings, _, _):
                    if let image = downsampledImage(contentsOfFile: wallpaperPath(file.resource, settings: settings), maxPixelSize: max(size.width, size.height) * System.backingScale) {
                        backgroundMode = .background(image: image, intensity: settings.intensity, colors: settings.colors.map { NSColor(argb: $0) }, rotation: settings.rotation, metadata: nil)
                    } else {
                        backgroundMode = TelegramPresentationTheme.defaultBackground(palette)
                    }
                case .none:
                    backgroundMode = .color(color: palette.chatBackground)
                case let .custom(representation, blurred):
                    if let image = downsampledImage(contentsOfFile: wallpaperPath(representation.resource, settings: WallpaperSettings(blur: blurred)), maxPixelSize: max(size.width, size.height) * System.backingScale) {
                        backgroundMode = .background(image: image, intensity: nil, colors: nil, rotation: nil, metadata: nil)
                    } else {
                        backgroundMode = TelegramPresentationTheme.defaultBackground(palette)
                    }
                case let .emoticon(emoticon):
                    if let first = emoticonThemes.first(where: { $0.0.id == emoticon.strippedEmoji }) {
                        backgroundMode = first.1.backgroundMode
                    } else {
                        backgroundMode = .plain
                    }
                }
            } else {
                backgroundMode = .color(color: palette.chatBackground)
            }
            
            func applyBubbles() {
                
                ctx.draw(TelegramThemeHooks.shared.image(.iconThemePreviewDino).precomposed(flipVertical: true), in: NSMakeRect(10, 24, 24, 24))
                ctx.draw(TelegramThemeHooks.shared.image(.iconThemePreviewDuck).precomposed(flipVertical: true), in: NSMakeRect(10, 54, 24, 24))

                let bubble1 = generateImage(NSMakeSize(80, 38), rotatedContext: { size, ctx in
                    let rect = NSMakeRect(0, 0, size.width, size.height)
                    ctx.clear(rect)
                    ctx.round(size, 12)
                    ctx.setFillColor(palette.bubbleBackground_incoming.cgColor)
                    ctx.fill(rect)
                })!
                
                ctx.draw(bubble1, in: NSMakeRect(40, 10, 80, 38))
                
                let bubble1Text1 = generateImage(NSMakeSize(62, 6), rotatedContext: { size, ctx in
                    let rect = NSMakeRect(0, 0, size.width, size.height)
                    ctx.clear(rect)
                    ctx.round(size, size.height / 2)
                    ctx.setFillColor(palette.grayText.withAlphaComponent(0.5).cgColor)
                    ctx.fill(rect)
                })!
                ctx.draw(bubble1Text1, in: NSMakeRect(49, 19, 62, 6))
                
                let bubble1Text2 = generateImage(NSMakeSize(38, 6), rotatedContext: { size, ctx in
                    let rect = NSMakeRect(0, 0, size.width, size.height)
                    ctx.clear(rect)
                    ctx.round(size, size.height / 2)
                    ctx.setFillColor(palette.grayText.withAlphaComponent(0.5).cgColor)
                    ctx.fill(rect)
                })!
                ctx.draw(bubble1Text2, in: NSMakeRect(49, 33, 38, 6))

                
                let bubble2 = generateImage(NSMakeSize(54, 24), rotatedContext: { size, ctx in
                    let rect = NSMakeRect(0, 0, size.width, size.height)
                    ctx.clear(rect)
                    ctx.round(size, 12)
                    ctx.setFillColor(palette.bubbleBackground_incoming.cgColor)
                    ctx.fill(rect)
                })!
                
                ctx.draw(bubble2, in: NSMakeRect(40, 54, 54, 24))
                
                let bubble2Text1 = generateImage(NSMakeSize(36, 6), rotatedContext: { size, ctx in
                    let rect = NSMakeRect(0, 0, size.width, size.height)
                    ctx.clear(rect)
                    ctx.round(size, size.height / 2)
                    ctx.setFillColor(palette.grayText.withAlphaComponent(0.5).cgColor)
                    ctx.fill(rect)
                })!
                ctx.draw(bubble2Text1, in: NSMakeRect(49, 63, 36, 6))
            }
            
            func applyPlain() {
                ctx.draw(TelegramThemeHooks.shared.image(.iconThemePreviewDino).precomposed(flipVertical: true), in: NSMakeRect(10, 10, 24, 24))
                if true {
                    let name1 = generateImage(NSMakeSize(32, 6), rotatedContext: { size, ctx in
                        let rect = NSMakeRect(0, 0, size.width, size.height)
                        ctx.clear(rect)
                        ctx.round(size, size.height / 2)
                        ctx.setFillColor(palette.peerAvatarGreenTop.cgColor)
                        ctx.fill(rect)
                    })!
                    ctx.draw(name1, in: NSMakeRect(42, 13, name1.backingSize.width, name1.backingSize.height))
                    
                    let text1 = generateImage(NSMakeSize(80, 6), rotatedContext: { size, ctx in
                        let rect = NSMakeRect(0, 0, size.width, size.height)
                        ctx.clear(rect)
                        ctx.round(size, size.height / 2)
                        ctx.setFillColor(palette.grayText.withAlphaComponent(0.5).cgColor)
                        ctx.fill(rect)
                    })!
                    ctx.draw(text1, in: NSMakeRect(42, 25, text1.backingSize.width, text1.backingSize.height))
                    
                    let text2 = generateImage(NSMakeSize(48, 6), rotatedContext: { size, ctx in
                        let rect = NSMakeRect(0, 0, size.width, size.height)
                        ctx.clear(rect)
                        ctx.round(size, size.height / 2)
                        ctx.setFillColor(palette.grayText.withAlphaComponent(0.5).cgColor)
                        ctx.fill(rect)
                    })!
                    ctx.draw(text2, in: NSMakeRect(42, 37, text2.backingSize.width, text2.backingSize.height))

                }
                
                if true {
                    ctx.draw(TelegramThemeHooks.shared.image(.iconThemePreviewDuck).precomposed(flipVertical: true), in: NSMakeRect(10, 54, 24, 24))

                    let name1 = generateImage(NSMakeSize(32, 6), rotatedContext: { size, ctx in
                        let rect = NSMakeRect(0, 0, size.width, size.height)
                        ctx.clear(rect)
                        ctx.round(size, size.height / 2)
                        ctx.setFillColor(palette.peerAvatarVioletTop.cgColor)
                        ctx.fill(rect)
                    })!
                    ctx.draw(name1, in: NSMakeRect(42, 57, name1.backingSize.width, name1.backingSize.height))
                    
                    let text1 = generateImage(NSMakeSize(80, 6), rotatedContext: { size, ctx in
                        let rect = NSMakeRect(0, 0, size.width, size.height)
                        ctx.clear(rect)
                        ctx.round(size, size.height / 2)
                        ctx.setFillColor(palette.grayText.withAlphaComponent(0.5).cgColor)
                        ctx.fill(rect)
                    })!
                    ctx.draw(text1, in: NSMakeRect(42, 69, text1.backingSize.width, text1.backingSize.height))
                }
            }
            drawBg(backgroundMode, palette: palette, bubbled: bubbled, rect: rect, in: ctx)
            if bubbled {
                applyBubbles()
            } else {
                applyPlain()
            }
        })!
        
        subscriber.putNext(image)
        subscriber.putCompletion()
        
        return EmptyDisposable
    } |> runOn(Queue.concurrentDefaultQueue())
}

public func generateChatThemeThumb(palette: ColorPalette, bubbled: Bool, backgroundMode: TableBackgroundMode) -> Signal<CGImage, NoError> {
    return Signal { subscriber in
        let image = generateImage(NSMakeSize(70, 80), rotatedContext: { size, ctx in
            let rect = NSMakeRect(0, 0, size.width, size.height)
            ctx.clear(rect)
            ctx.round(size, 10)
            
            func applyBubbles() {
                let bubbleImage = TelegramThemeHooks.shared.image(.iconThemeBubble)
                let incoming = bubbleImage.precomposed(palette.bubbleBackground_incoming, flipVertical: true)
                ctx.draw(incoming, in: NSMakeRect(7, 9, 38, 16))
                let outgoing = bubbleImage.precomposed(palette.bubbleBackground_outgoing, flipVertical: true, flipHorizontal: true)
                ctx.draw(outgoing, in: NSMakeRect(size.width - 47, 9 + 16 + 5, 38, 16))
            }
            
            func applyPlain() {
                ctx.setFillColor(palette.accent.cgColor)
                ctx.fillEllipse(in: NSMakeRect(5, 7, 17, 17))
                
                if true {
                    let name1 = generateImage(NSMakeSize(20, 4), rotatedContext: { size, ctx in
                        let rect = NSMakeRect(0, 0, size.width, size.height)
                        ctx.clear(rect)
                        ctx.round(size, 2)
                        ctx.setFillColor(palette.accent.cgColor)
                        ctx.fill(rect)
                    })!
                    ctx.draw(name1, in: NSMakeRect(5 + 17 + 3, 7 + 2, name1.backingSize.width, name1.backingSize.height))
                    
                    let text1 = generateImage(NSMakeSize(40, 4), rotatedContext: { size, ctx in
                        let rect = NSMakeRect(0, 0, size.width, size.height)
                        ctx.clear(rect)
                        ctx.round(size, 2)
                        ctx.setFillColor(palette.grayText.withAlphaComponent(0.5).cgColor)
                        ctx.fill(rect)
                    })!
                    ctx.draw(text1, in: NSMakeRect(5 + 17 + 3, 7 + 2 + 4 + 4, text1.backingSize.width, text1.backingSize.height))
                }
                
                if true {
                    ctx.setFillColor(palette.accent.cgColor)
                    ctx.fillEllipse(in: NSMakeRect(5, 7 + 17 + 7, 17, 17))
                    
                    let name1 = generateImage(NSMakeSize(20, 4), rotatedContext: { size, ctx in
                        let rect = NSMakeRect(0, 0, size.width, size.height)
                        ctx.clear(rect)
                        ctx.round(size, 2)
                        ctx.setFillColor(palette.accent.cgColor)
                        ctx.fill(rect)
                    })!
                    ctx.draw(name1, in: NSMakeRect(5 + 17 + 3, 7 + 17 + 7 + 2, name1.backingSize.width, name1.backingSize.height))
                    
                    let text1 = generateImage(NSMakeSize(40, 4), rotatedContext: { size, ctx in
                        let rect = NSMakeRect(0, 0, size.width, size.height)
                        ctx.clear(rect)
                        ctx.round(size, 2)
                        ctx.setFillColor(palette.grayText.withAlphaComponent(0.5).cgColor)
                        ctx.fill(rect)
                    })!
                    ctx.draw(text1, in: NSMakeRect(5 + 17 + 3, 7 + 17 + 7 + 2 + 4 + 4, text1.backingSize.width, text1.backingSize.height))
                }
                
                
            }
            drawBg(backgroundMode, palette: palette, bubbled: bubbled, rect: rect, in: ctx)
            if bubbled {
                applyBubbles()
            } else {
                applyPlain()
            }
            
        })!
        
        subscriber.putNext(image)
        subscriber.putCompletion()
        
        return EmptyDisposable
    } |> runOn(Queue.concurrentDefaultQueue())
}




public func themeAppearanceThumbAndData(context: any AccountContextProtocol, bubbled: Bool, parent: ColorPalette, source: ThemeSource, thumbSource: AppearanceThumbSource = .general) -> Signal<(TransformImageResult, InstallThemeSource), NoError> {
    
    var thumbGenerator = generateThumb
    switch thumbSource {
    case .widget:
        thumbGenerator = generateWidgetThumb
    case .general:
        thumbGenerator = generateThumb
    }
    
    switch source {
    case let .cloud(cloud):
        if let file = cloud.file {
            return cloudThemeData(context: context, theme: cloud, file: file) |> mapToSignal { data in
                return thumbGenerator(data.0, bubbled, data.1, context.emoticonThemes) |> map { image in
                    return (TransformImageResult(image, true), .cloud(cloud, InstallCloudThemeCachedData(palette: data.0, wallpaper: data.1, cloudWallpaper: data.2)))
                }
            }
        } else if let palette = cloud.effectiveSettings(for: parent)?.palette {
            
            
            let settings = themeSettingsView(accountManager: context.sharedContext.accountManager) |> take(1)
            
            return settings |> map { settings -> (Wallpaper, ColorPalette) in
                let settings = settings
                    .withUpdatedPalette(palette)
                    .withUpdatedCloudTheme(cloud)
                    .installDefaultAccent()
                    .installDefaultWallpaper()
                return (settings.wallpaper.wallpaper, settings.palette)
            } |> mapToSignal { wallpaper, palette in
                return thumbGenerator(palette, bubbled, wallpaper, context.emoticonThemes) |> map { image in
                    return (TransformImageResult(image, true), .cloud(cloud, InstallCloudThemeCachedData(palette: palette, wallpaper: wallpaper, cloudWallpaper: cloud.effectiveSettings(for: palette)?.wallpaper)))
                }
            }
        } else {
            return .single((TransformImageResult(theme.icons.appearanceAddPlatformTheme, true), .cloud(cloud, nil)))
        }
    case let .local(palette, cloud):
        let settings = themeSettingsView(accountManager: context.sharedContext.accountManager) |> take(1)
        
        return settings |> map { settings -> (Wallpaper, ColorPalette) in
            let settings = settings
                .withUpdatedPalette(palette)
                .withUpdatedCloudTheme(cloud)
                .installDefaultAccent()
                .installDefaultWallpaper()
            return (settings.wallpaper.wallpaper, settings.palette)
        } |> mapToSignal { wallpaper, palette in
            if let cloud = cloud {
                return thumbGenerator(palette, bubbled, wallpaper, context.emoticonThemes) |> map { image in
                    return (TransformImageResult(image, true), .cloud(cloud, InstallCloudThemeCachedData(palette: palette, wallpaper: wallpaper, cloudWallpaper: cloud.effectiveSettings(for: palette)?.wallpaper)))
                }
            } else {
                return thumbGenerator(palette, bubbled, wallpaper, context.emoticonThemes) |> map { image in
                    return (TransformImageResult(image, true), .local(palette))
                }
            }
        }
    }
}




