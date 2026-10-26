import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import FenixuzCore

// App Store 3.1.1: the app sells no digital goods through StoreKit. Every Premium, Stars,
// gift and giveaway purchase goes through this manager, which shows the blocked alert and
// fails with `.cantMakePayments` (callers close their lock modal only on error). Product
// lists and the "can make payments" state come from the real manager, so screens look as before.
final class FenixuzBlockingPurchaseManager: InAppPurchaseManagerProtocol {
    private let base: any InAppPurchaseManagerProtocol
    private let window: () -> Window?

    init(base: any InAppPurchaseManagerProtocol, window: @escaping () -> Window?) {
        self.base = base
        self.window = window
    }

    var canMakePayments: Bool {
        return base.canMakePayments
    }

    var availableProducts: Signal<[InAppPurchaseProduct], NoError> {
        return base.availableProducts
    }

    func finishAllTransactions() {
        base.finishAllTransactions()
    }

    func restorePurchases(completion: @escaping (InAppPurchaseRestoreState) -> Void) {
        presentAlert()
        completion(.succeed(false))
    }

    func buyProduct(_ product: InAppPurchaseProduct, quantity: Int32, purpose: AppStoreTransactionPurpose) -> Signal<InAppPurchaseState, InAppPurchaseError> {
        return Signal { [weak self] subscriber in
            self?.presentAlert()
            subscriber.putError(.cantMakePayments)
            return EmptyDisposable
        } |> runOn(.mainQueue())
    }

    private func presentAlert() {
        Queue.mainQueue().async { [weak self] in
            FenixuzAppStoreIAP.presentBlockedAlert(on: self?.window() ?? mainWindow)
        }
    }
}
