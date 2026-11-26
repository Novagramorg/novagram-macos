import Cocoa
import TGUIKit
import TelegramCore
import ThemeSettings
import InAppSettings
import SwiftSignalKit
import Postbox
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import TelegramIconsTheme
import TelegramMediaUtils


public final class SettingsThemeWallpaperView: BackgroundView {
    private var wallpaper: Wallpaper?
    public let imageView = TransformImageView()
    private let fetchDisposable = MetaDisposable()
    public var delete: (() -> Void)?
    private let label: TextView = TextView()
    public init() {
        super.init(frame: NSZeroRect)
        layer?.borderColor = theme.colors.border.cgColor
        layer?.borderWidth = .borderSize
        self.addSubview(self.imageView)
        label.isEventLess = true
        label.userInteractionEnabled = false
        label.isSelectable = false
        let layout = TextViewLayout(.initialize(string: strings().chatWallpaperEmpty, color: theme.colors.grayText, font: .normal(.title)), maximumNumberOfLines: 1)
        layout.measure(width: .greatestFiniteMagnitude)
        label.update(layout)
        label.backgroundColor = theme.chatBackground
        label.disableBackgroundDrawing = true
    }
    
    deinit {
        fetchDisposable.dispose()
    }

    
    public override func layout() {
        super.layout()
        label.center()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public func setWallpaper(account: Account, wallpaper: Wallpaper, size: CGSize) {
        self.imageView.frame = CGRect(origin: CGPoint(), size: size)
        
        
        
        self.wallpaper = wallpaper
        switch wallpaper {
        case .builtin:
            self.label.isHidden = true
            self.imageView.isHidden = false
            
            let media = TelegramMediaImage(imageId: MediaId(namespace: 0, id: -1), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
            let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: CGSize(), boundingSize: size, intrinsicInsets: NSEdgeInsets())
            self.imageView.setSignal(signal: cachedMedia(media: media, arguments: arguments, scale: backingScaleFactor))
            
            
            self.imageView.setSignal(settingsBuiltinWallpaperImage(account: account, scale: backingScaleFactor), cacheImage: { [weak media] result in
                if let media = media {
                    cacheMedia(result, media: media, arguments: arguments, scale: System.backingScale)
                }
            })
            
            self.imageView.set(arguments: arguments)
            
            self.backgroundMode = TelegramPresentationTheme.defaultBackground(theme.colors)

        case let .color(color):
            self.imageView.isHidden = true
            self.label.isHidden = true
            self.backgroundMode = .color(color: NSColor(UInt32(color)))
        case let .gradient(_, colors, rotation):
            self.imageView.isHidden = true
            self.label.isHidden = true
            self.backgroundMode = .gradient(colors: colors.map { NSColor(argb: $0) }, rotation: rotation)
        case let .image(representations, _):
            self.label.isHidden = true
            self.imageView.isHidden = false
            self.imageView.setSignal(chatWallpaper(account: account, representations: representations, mode: .thumbnail, isPattern: false, autoFetchFullSize: true, scale: backingScaleFactor))
            self.imageView.set(arguments: TransformImageArguments(corners: ImageCorners(), imageSize: largestImageRepresentation(representations)!.dimensions.size.aspectFilled(size), boundingSize: size, intrinsicInsets: NSEdgeInsets(), emptyColor: nil))
            self.backgroundMode = .plain
            fetchDisposable.set(fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.wallpaper(wallpaper: nil, resource: largestImageRepresentation(representations)!.resource)).start())
        case let .file(slug, file, settings, isPattern, _):
            self.label.isHidden = true
            self.imageView.isHidden = false
            var patternColor: TransformImageEmptyColor? = nil// = NSColor(rgb: 0xd6e2ee, alpha: 0.5)

            var representations:[TelegramMediaImageRepresentation] = []
            if let dimensions = file.dimensions {
                representations.append(TelegramMediaImageRepresentation(dimensions: dimensions, resource: file.resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
            } else {
                representations.append(TelegramMediaImageRepresentation(dimensions: PixelDimensions(NSMakeSize(600, 600)), resource: file.resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false))
            }
            
            let sz = largestImageRepresentation(representations)?.dimensions.size ?? size
            
            if isPattern {
                var patternIntensity: CGFloat = 0.5
                if let intensity = settings.intensity {
                    patternIntensity = CGFloat(intensity) / 100.0
                }
                if settings.colors.count == 1, let color = settings.colors.first {
                    patternColor = .color(NSColor(rgb: color, alpha: patternIntensity))
                } else {
                    patternColor = .gradient(colors: settings.colors.map { NSColor(rgb: $0) }, intensity: patternIntensity, rotation: settings.rotation)
                }
            }
            
            let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: sz.aspectFilled(isPattern ? NSMakeSize(300, 300) : size), boundingSize: size, intrinsicInsets: NSEdgeInsets(), emptyColor: patternColor)
            
            let signal = chatWallpaper(account: account, representations: representations, file: file, mode: .thumbnail, isPattern: isPattern, autoFetchFullSize: true, scale: backingScaleFactor)
            
            self.imageView.setSignal(signal: cachedMedia(media: file, arguments: arguments, scale: System.backingScale))
            
            if !self.imageView.isFullyLoaded {
                self.imageView.setSignal(signal, clearInstantly: false, cacheImage: { result in
                    cacheMedia(result, media: file, arguments: arguments, scale: System.backingScale)
                })
            }
            


            self.imageView.set(arguments: arguments)

            
            fetchDisposable.set(fetchedMediaResource(mediaBox: account.postbox.mediaBox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.wallpaper(wallpaper: .slug(slug), resource: largestImageRepresentation(representations)!.resource)).start())
            
            self.backgroundMode = .plain
        default:
            self.backgroundMode = .plain
        }
    }
    
}

