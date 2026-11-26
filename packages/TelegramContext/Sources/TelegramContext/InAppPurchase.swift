import Foundation
import StoreKit
import SwiftSignalKit
import TelegramCore
import CurrencyFormat

private func isSubscriptionProductId(_ id: String) -> Bool {
    return id.hasSuffix(".monthly") || id.hasSuffix(".annual") || id.hasSuffix(".semiannual")
}

private extension NSDecimalNumber {
    func round(_ decimals: Int) -> NSDecimalNumber {
        return self.rounding(accordingToBehavior:
                            NSDecimalNumberHandler(roundingMode: .down,
                                   scale: Int16(decimals),
                                   raiseOnExactness: false,
                                   raiseOnOverflow: false,
                                   raiseOnUnderflow: false,
                                   raiseOnDivideByZero: false))
    }
}

public final class InAppPurchaseProduct: Equatable {
    private lazy var numberFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .currency
        numberFormatter.locale = self.skProduct.priceLocale
        return numberFormatter
    }()
    
    public let skProduct: SKProduct
    
    public init(skProduct: SKProduct) {
        self.skProduct = skProduct
    }
    
    public var id: String {
        return self.skProduct.productIdentifier
    }
    
    public var isSubscription: Bool {
        if #available(macOS 10.14, *) {
            return self.skProduct.subscriptionGroupIdentifier != nil
        } else {
            if #available(macOS 10.13.2, *) {
                return self.skProduct.subscriptionPeriod != nil
            } else {
                return isSubscriptionProductId(self.skProduct.productIdentifier)
            }
        }
    }
    
    public var price: String {
        return self.numberFormatter.string(from: self.skProduct.price) ?? ""
    }
    
    public func pricePerMonth(_ monthsCount: Int) -> String {
        let price = self.skProduct.price.dividing(by: NSDecimalNumber(value: monthsCount)).round(2)
        return self.numberFormatter.string(from: price) ?? ""
    }
    
    public func defaultPrice(_ value: NSDecimalNumber, monthsCount: Int) -> String {
        let price = value.multiplying(by: NSDecimalNumber(value: monthsCount)).round(2)
        let prettierPrice = price
            .multiplying(by: NSDecimalNumber(value: 2))
            .rounding(accordingToBehavior:
                NSDecimalNumberHandler(
                    roundingMode: .up,
                    scale: Int16(0),
                    raiseOnExactness: false,
                    raiseOnOverflow: false,
                    raiseOnUnderflow: false,
                    raiseOnDivideByZero: false
                )
            )
            .dividing(by: NSDecimalNumber(value: 2))
            .subtracting(NSDecimalNumber(value: 0.01))
        return self.numberFormatter.string(from: prettierPrice) ?? ""
    }
    
    public func multipliedPrice(count: Int) -> String {
        let price = self.skProduct.price.multiplying(by: NSDecimalNumber(value: count)).round(2)
        let prettierPrice = price
            .multiplying(by: NSDecimalNumber(value: 2))
            .rounding(accordingToBehavior:
                NSDecimalNumberHandler(
                    roundingMode: .up,
                    scale: Int16(0),
                    raiseOnExactness: false,
                    raiseOnOverflow: false,
                    raiseOnUnderflow: false,
                    raiseOnDivideByZero: false
                )
            )
            .dividing(by: NSDecimalNumber(value: 2))
            .subtracting(NSDecimalNumber(value: 0.01))
        return self.numberFormatter.string(from: prettierPrice) ?? ""
    }
    
    public var priceValue: NSDecimalNumber {
        return self.skProduct.price
    }
    
    public var priceCurrencyAndAmount: (currency: String, amount: Int64) {
        if let currencyCode = self.numberFormatter.currencyCode,
            let amount = fractionalToCurrencyAmount(value: self.priceValue.doubleValue, currency: currencyCode) {
            return (currencyCode, amount)
        } else {
            return ("", 0)
        }
    }
    
    public static func ==(lhs: InAppPurchaseProduct, rhs: InAppPurchaseProduct) -> Bool {
        if lhs.id != rhs.id {
            return false
        }
        if lhs.isSubscription != rhs.isSubscription {
            return false
        }
        if lhs.priceValue != rhs.priceValue {
            return false
        }
        return true
    }
    
}

public enum InAppPurchaseState {
    case purchased(transactionId: String)
}

public enum InAppPurchaseError {
    case generic
    case cancelled
    case network
    case notAllowed
    case cantMakePayments
    case assignFailed
}

public enum InAppPurchaseRestoreState {
    case succeed(Bool)
    case failed
}

public protocol InAppPurchaseManagerProtocol: AnyObject {
    var canMakePayments: Bool { get }
    var availableProducts: Signal<[InAppPurchaseProduct], NoError> { get }
    func restorePurchases(completion: @escaping (InAppPurchaseRestoreState) -> Void)
    func finishAllTransactions()
    func buyProduct(_ product: InAppPurchaseProduct, quantity: Int32, purpose: AppStoreTransactionPurpose) -> Signal<InAppPurchaseState, InAppPurchaseError>
}

extension InAppPurchaseManagerProtocol {
    public func buyProduct(_ product: InAppPurchaseProduct, purpose: AppStoreTransactionPurpose) -> Signal<InAppPurchaseState, InAppPurchaseError> {
        return buyProduct(product, quantity: 1, purpose: purpose)
    }
}

public struct PremiumGiftProduct: Equatable {
    public init(giftOption: PremiumGiftCodeOption, storeProduct: InAppPurchaseProduct?) {
        self.giftOption = giftOption
        self.storeProduct = storeProduct
    }

    public let giftOption: PremiumGiftCodeOption
    public let storeProduct: InAppPurchaseProduct?
    
    public var id: String {
        return self.storeProduct?.id ?? ""
    }
    
    public var months: Int32 {
        return self.giftOption.months
    }
    
    public var price: String {
        if let storeProduct = storeProduct {
            return formatCurrencyAmount(storeProduct.priceCurrencyAndAmount.amount, currency: storeProduct.priceCurrencyAndAmount.currency)
        }
        return formatCurrencyAmount(giftOption.amount, currency: giftOption.currency)
    }
    
    public var pricePerMonth: String {
        if let storeProduct = storeProduct {
            return storeProduct.pricePerMonth(Int(self.months))
        } else {
            return formatCurrencyAmount(giftOption.amount / Int64(giftOption.months), currency: giftOption.currency)
        }
    }
    public var priceCurrencyAndAmount:(currency: String, amount: Int64) {
        if let storeProduct = storeProduct {
            return storeProduct.priceCurrencyAndAmount
        } else {
            return (currency: giftOption.currency, amount: giftOption.amount)
        }
    }
    
    public func multipliedPrice(count: Int) -> String {
        if let storeProduct = storeProduct {
            return storeProduct.multipliedPrice(count: count)
        } else {
            return formatCurrencyAmount(giftOption.amount * Int64(count), currency: giftOption.currency)
        }
    }
}
