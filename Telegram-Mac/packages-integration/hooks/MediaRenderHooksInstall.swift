import Cocoa
import TGUIKit

func installMediaRenderHooks() {
    MediaRenderHooks.install(MediaRenderHooks(themePreview: { palette, wallpaper, backgroundMode in
        return generateThemePreview(for: palette, wallpaper: wallpaper, backgroundMode: backgroundMode)
    }, drawBackground: { backgroundMode, palette, bubbled, rect, ctx in
        drawBg(backgroundMode, palette: palette, bubbled: bubbled, rect: rect, in: ctx)
    }, topicIcon: { size, backgroundColors, strokeColors, title in
        return generateTopicIcon(size: size, backgroundColors: backgroundColors, strokeColors: strokeColors, title: title)
    }, diceCache: {
        return currentDiceCache
    }, startModalPreview: { table, window, context in
        guard let context = context as? AccountContext else {
            return
        }
        startModalPreviewHandle(table, window: window, context: context)
    }))
}
