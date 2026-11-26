import Foundation

public struct PaymentsPaymentMethodAdditionalFields: OptionSet {
    public var rawValue: Int32
    
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }
    
    public static let cardholderName = PaymentsPaymentMethodAdditionalFields(rawValue: 1 << 0)
    public static let country = PaymentsPaymentMethodAdditionalFields(rawValue: 1 << 1)
    public static let zipCode = PaymentsPaymentMethodAdditionalFields(rawValue: 1 << 2)
}
