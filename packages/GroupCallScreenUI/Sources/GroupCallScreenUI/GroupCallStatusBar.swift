import Cocoa
import Foundation
import SwiftSignalKit
import TGUIKit
import ColorPalette
import Localization
import TelegramContext
import TelegramTheme
import GeneralRows

private let statusAnimationStepCount = 12

private let statusAnimationFrames: [NSImage] = {
    let forward = (0 ..< statusAnimationStepCount).map { step -> NSImage in
        let progress = CGFloat(step) / CGFloat(statusAnimationStepCount - 1)
        return generateStatus(alpha: 0.3 + 0.7 * progress)
    }
    return forward + forward.reversed()
}()

private func generateStatus(alpha: CGFloat) -> NSImage {
    let image = generateImage(NSMakeSize(24, 20), rotatedContext: { size, ctx in
        ctx.clear(size.bounds)
        ctx.setFillColor(darkPalette.redUI.withAlphaComponent(alpha).cgColor)
        ctx.fillEllipse(in: NSMakeRect(6, 5, 10, 10))
    })
    return NSImage(cgImage: image!, size: image!.systemSize)
}

public final class GroupCallStatusBar {
    private let disposable = MetaDisposable()
    private let sharedContext: any SharedAccountContextProtocol
    
    private var animator: SwiftSignalKit.Timer? = nil {
        didSet {
            oldValue?.invalidate()
        }
    }
    private let arguments: GroupCallUIArguments
    public init(_ signal: Signal<GroupCallUIState, NoError>, arguments: GroupCallUIArguments, sharedContext: any SharedAccountContextProtocol) {
        self.sharedContext = sharedContext
        self.arguments = arguments
        disposable.set(signal.start(next: { [weak self] state in
            self?.updateState(state)
        }))
    }
    private var previous: Bool? = nil
    private func updateState(_ state: GroupCallUIState) {
        let hasShare = state.hasScreencast || state.hasVideo
        
        var items:[ContextMenuItem] = []
        if state.hasScreencast {
            items.append(.init(strings().groupCallStatusBarStopScreen, handler: { [weak self] in
                self?.arguments.cancelShareScreencast()
            }, image: TelegramThemeHooks.shared.image(.groupCallStopShareScreen)))
        } else if !state.cantRunVideo {
            items.append(.init(strings().groupCallStatusBarStartScreen, handler: { [weak self] in
                self?.arguments.shareSource(.screencast, true)
            }, image: TelegramThemeHooks.shared.image(.groupCallShareScreen)))
        }
        if state.hasVideo {
            items.append(.init(strings().groupCallStatusBarStopVideo, handler: { [weak self] in
                self?.arguments.cancelShareVideo()
            }, image: TelegramThemeHooks.shared.image(.groupCallStopShareVideo)))
        } else if !state.cantRunVideo {
            items.append(.init(strings().groupCallStatusBarStartVideo, handler: { [weak self] in
                self?.arguments.shareSource(.video, true)
            }, image: TelegramThemeHooks.shared.image(.groupCallShareVideo)))
        }
        
        if !items.isEmpty {
            self.sharedContext.callStatusBarMenuItems = {
                return items
            }
        } else {
            self.sharedContext.callStatusBarMenuItems = nil
        }
        
        
        if hasShare != previous {
            if hasShare {
                self.runAnimator()
            } else {
                GroupCallScreenUIHooks.shared.forceUpdateStatusBarIconByDockTile(sharedContext)
                self.animator = nil
            }
        }
        self.previous = hasShare
    }
    
    private func clear() {
        GroupCallScreenUIHooks.shared.forceUpdateStatusBarIconByDockTile(sharedContext)
        self.animator = nil
        self.sharedContext.callStatusBarMenuItems = nil
    }
    

    private var frameIndex: Int = 0
    private func runAnimator() {
        let frames = statusAnimationFrames
        frameIndex = 0
        let timer = SwiftSignalKit.Timer(timeout: 1.5 / Double(statusAnimationStepCount), repeat: true, completion: { [weak self] in
            guard let self else {
                return
            }
            self.sharedContext.updateStatusBarImage(frames[self.frameIndex % frames.count])
            self.frameIndex += 1
        }, queue: .mainQueue())
        self.animator = timer
        timer.start()
    }
    
    deinit {
        disposable.dispose()
        clear()
    }
}
