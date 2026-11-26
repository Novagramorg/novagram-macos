import Foundation
import TGUIKit
import TelegramMedia
import Cocoa
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import LocalAnimations
import InputTextView

public final class TranscribeAudioTextView : View {
    private let textView = FoldingTextView(frame: .zero)
    private var lottiePlayer: LottiePlayerView?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
    }

    public override func layout() {
        super.layout()
        self.updateLayout(size: frame.size, transition: .immediate)
    }


    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: textView, frame: textView.frame.size.bounds)
        updateDots(size: size, transition: transition)
    }

    private func updateDots(size: NSSize, transition: ContainedViewLayoutTransition) {
        if let last = textView.textLayouts.last?.lines.last {
            if let view = lottiePlayer {
                let x: CGFloat
                if last.frame.maxX + view.frame.width > size.width {
                    x = -3
                } else {
                    x = last.frame.maxX
                }
                transition.updateFrame(view: view, frame: CGRect(origin: CGPoint(x: x, y: size.height - view.frame.height + 1), size: view.frame.size))
            }
        }
    }

    public func update(data: ChatMediaVoiceLayoutParameters.TranscribeData, animated: Bool) {
        if let textLayout = data.text {
            textView.update(layout: textLayout, animated: animated, appendingAnimationView: data.isPending ? lottiePlayer : nil)
        }

        let size = data.dotsSize
        if data.isPending, let dataSize = data.size {
            let current: LottiePlayerView
            if let view = lottiePlayer ?? textView.appendingAnimationView {
                current = view
            } else {
                current = LottiePlayerView()
                current.setFrameSize(size)
                self.lottiePlayer = current
                addSubview(current)

                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
                let animation = LocalAnimatedSticker.voice_dots
                if let compressed = animation.data {
                    let colors: [LottieColor] = [LottieColor(keyPath: "", color: data.fontColor)]
                    current.set(LottieAnimation(compressed: compressed, key: .init(key: .bundle("dots_\(animation.rawValue)"), size: size, colors: colors), playPolicy: .loop, colors: colors))
                }
            }
            updateDots(size: dataSize, transition: .immediate)
        } else if let view = lottiePlayer {
            self.lottiePlayer = nil
            performSubviewRemoval(view, animated: animated)
        }


    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
