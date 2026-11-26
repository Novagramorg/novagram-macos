from pathlib import Path
lab = Path(__file__).resolve().parent
root = lab.parents[2]
s = (root / 'packages/StarsUI/Sources/StarsUI/StarGift_Nft_Controller.swift').read_text()
action = s[s.index('    public class ActionView : Control {'):s.index('    private var timer:', s.index('    public class ActionView : Control {'))]
action = action.replace('public ', '')
qr = (root / 'packages/QrStudioUI/Sources/QrStudioUI/QrStudioGlassButtonView.swift').read_text()
appearance = qr[qr.index('struct QrStudioGlassAppearance:'):qr.index('enum QrStudioGlass {')]
qr = qr[qr.index('final class QrStudioGlassButtonView:'):]
motion = (root / 'packages/QrStudioUI/Sources/QrStudioUI/QrStudioMotion.swift').read_text()
stack = motion[motion.index('struct QrStudioStageStack<Item>'):motion.index('enum QrStudioSweep {')]
(lab / 'Sources/GiftControls/Generated.swift').write_text('import Cocoa\nimport TGUIKit\n' + action + appearance + qr + stack)

wallet = (root / 'packages/WalletUI/Sources/WalletUI/WalletCollectibleArtwork.swift').read_text()
cache = wallet[wallet.index('final class WalletCollectibleArtworks {'):wallet.index('    private func apply(_ gift:')]
cache += """
    private func apply(_ gift: StarGift.UniqueGift, address: String, postbox: Postbox) {
        update(address) { $0.gift = gift; $0.art = true }
    }
    private func loadModel(_ file: TelegramMediaFile, address: String, postbox: Postbox) {
        guard requestedModels[address] != file.fileId else { return }
        requestedModels[address] = file.fileId
        update(address) { $0.modelFile = Data([UInt8(file.fileId)]) }
    }
}
"""
peer = (root / 'packages/WalletUI/Sources/WalletUI/WalletPeerBalanceController.swift').read_text()
preload = peer[peer.index('@available(macOS 10.15, *)\npublic func preloadWalletPeerCard'):].replace('public func', 'func')
(lab / 'Sources/GiftControls/GeneratedWallet.swift').write_text('import Cocoa\nimport SwiftSignalKit\n' + cache + preload)

text_view = (root / 'packages/GeneralRows/Sources/GeneralRows/InteractiveTextView.swift').read_text()
text_view = text_view[text_view.index('public final class InteractiveTextView'):].replace('public ', '')
(lab / 'Sources/GiftControls/GeneratedText.swift').write_text('import Cocoa\nimport TGUIKit\n' + text_view)
