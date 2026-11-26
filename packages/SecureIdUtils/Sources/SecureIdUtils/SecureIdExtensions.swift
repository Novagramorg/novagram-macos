import Foundation
import TelegramTheme
import Cocoa
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import TGPassportMRZ

public extension SentSecureValueType {
    var rawValue: String {
        switch self {
        case .email:
            return strings().secureIdRequestPermissionEmail
        case .phone:
            return strings().secureIdRequestPermissionPhone
        case .passport:
            return strings().secureIdRequestPermissionPassport
        case .address:
            return strings().secureIdRequestPermissionResidentialAddress
        case .personalDetails:
            return strings().secureIdRequestPermissionPersonalDetails
        case .driversLicense:
            return strings().secureIdRequestPermissionDriversLicense
        case .utilityBill:
            return strings().secureIdRequestPermissionUtilityBill
        case .rentalAgreement:
            return strings().secureIdRequestPermissionTenancyAgreement
        case .idCard:
            return strings().secureIdRequestPermissionIDCard
        case .bankStatement:
            return strings().secureIdRequestPermissionBankStatement
        case .internalPassport:
            return strings().secureIdRequestPermissionInternalPassport
        case .passportRegistration:
            return strings().secureIdRequestPermissionPassportRegistration
        case .temporaryRegistration:
            return strings().secureIdRequestPermissionTemporaryRegistration
        }
    }
}

extension UpdateTwoStepVerificationPasswordResult : @retroactive Equatable {
    public static func ==(lhs: UpdateTwoStepVerificationPasswordResult, rhs: UpdateTwoStepVerificationPasswordResult) -> Bool {
        switch lhs {
        case .none:
            if case .none = rhs {
                return true
            } else {
                return false
            }
        case let .password(password, lhsPendingEmailPattern):
            if case .password(password, let rhsPendingEmailPattern) = rhs {
                return lhsPendingEmailPattern == rhsPendingEmailPattern
            } else {
                return false
            }
        }
    }
}

public extension SecureIdGender {
    static func gender(from mrz: TGPassportMRZ) -> SecureIdGender {
        switch mrz.gender.lowercased() {
        case "f":
            return .female
        default:
            return .male
        }
    }
}

public extension SecureIdRequestedFormField {
    var isIdentityField: Bool {
        switch self {
        case let .just(field):
            switch field {
            case .idCard, .passport, .driversLicense, .internalPassport:
                return true
            default:
                return false
            }
        case let .oneOf(fields):
            switch fields[0] {
            case .idCard, .passport, .driversLicense, .internalPassport:
                return true
            default:
                return false
            }
        }
    }
    
    var valueKey: SecureIdValueKey? {
        switch self {
        case let .just(field):
            return field.valueKey
        default:
            return nil
        }
    }
    
    var fieldValue: SecureIdRequestedFormFieldValue? {
        switch self {
        case let .just(field):
            return field
        default:
            return nil
        }
    }
    
    var isAddressField: Bool {
        switch self {
        case let .just(field):
            switch field {
            case .utilityBill, .bankStatement, .rentalAgreement, .passportRegistration, .temporaryRegistration:
                return true
            default:
                return false
            }
        case let .oneOf(fields):
            switch fields[0] {
            case .utilityBill, .bankStatement, .rentalAgreement, .passportRegistration, .temporaryRegistration:
                return true
            default:
                return false
            }
        }
    }
}

public extension SecureIdForm {
    func searchContext(for field: SecureIdRequestedFormFieldValue) -> SecureIdValueWithContext? {
         let index = values.firstIndex(where: { context -> Bool in
            switch context.value {
            case .address:
                if case .address = field {
                    return true
                } else {
                    return false
                }
            case .bankStatement:
                if case .bankStatement = field {
                    return true
                } else {
                    return false
                }
            case .driversLicense:
                if case .driversLicense = field {
                    return true
                } else {
                    return false
                }
            case .idCard:
                if case .idCard = field {
                    return true
                } else {
                    return false
                }
            case .passport:
                if case .passport = field {
                    return true
                } else {
                    return false
                }
            case .personalDetails:
                if case .personalDetails = field {
                    return true
                } else {
                    return false
                }
            case .rentalAgreement:
                if case .rentalAgreement = field {
                    return true
                } else {
                    return false
                }
            case .utilityBill:
                if case .utilityBill = field {
                    return true
                } else {
                    return false
                }
            case .phone:
                if case .phone = field {
                    return true
                } else {
                    return false
                }
            case .email:
                if case .email = field {
                    return true
                } else {
                    return false
                }
            case .internalPassport:
                if case .internalPassport = field {
                    return true
                } else {
                    return false
                }
            case .passportRegistration:
                if case .passportRegistration = field {
                    return true
                } else {
                    return false
                }
            case .temporaryRegistration:
                if case .temporaryRegistration = field {
                    return true
                } else {
                    return false
                }
            }
        })
        if let index = index {
            return values[index]
        } else {
            return nil
        }
    }
    

}

public extension SecureIdValue {
    func isSame(of value: SecureIdValue) -> Bool {
        switch self {
        case .address:
            if case .address = value {
                return true
            } else {
                return false
            }
        case .bankStatement:
            if case .bankStatement = value {
                return true
            } else {
                return false
            }
        case .driversLicense:
            if case .driversLicense = value {
                return true
            } else {
                return false
            }
        case .idCard:
            if case .idCard = value {
                return true
            } else {
                return false
            }
        case .passport:
            if case .passport = value {
                return true
            } else {
                return false
            }
        case .personalDetails:
            if case .personalDetails = value {
                return true
            } else {
                return false
            }
        case .rentalAgreement:
            if case .rentalAgreement = value {
                return true
            } else {
                return false
            }
        case .utilityBill:
            if case .utilityBill = value {
                return true
            } else {
                return false
            }
        case .phone:
            if case .phone = value {
                return true
            } else {
                return false
            }
        case .email:
            if case .email = value {
                return true
            } else {
                return false
            }
        case .internalPassport(_):
            if case .internalPassport = value {
                return true
            } else {
                return false
            }
        case .passportRegistration(_):
            if case .passportRegistration = value {
                return true
            } else {
                return false
            }
        case .temporaryRegistration(_):
            if case .temporaryRegistration = value {
                return true
            } else {
                return false
            }
        }
    }
    func isSame(of value: SecureIdValueKey) -> Bool {
        return self.key == value
    }
    
    
    
    
    var addressValue: SecureIdAddressValue? {
        switch self {
        case let .address(value):
            return value
        default:
            return nil
        }
    }
    
    var identifier: String? {
        switch self {
        case let .passport(value):
            return value.identifier
        case let .driversLicense(value):
            return value.identifier
        case let .idCard(value):
            return value.identifier
        case let .internalPassport(value):
            return value.identifier
        default:
            return nil
        }
    }
    
    var personalDetails: SecureIdPersonalDetailsValue? {
        switch self {
        case let .personalDetails(value):
            return value
        default:
            return nil
        }
    }
    
    var selfieVerificationDocument: SecureIdVerificationDocumentReference? {
        switch self {
        case let .idCard(value):
            return value.selfieDocument
        case let .passport(value):
            return value.selfieDocument
        case let .driversLicense(value):
            return value.selfieDocument
        case let .internalPassport(value):
            return value.selfieDocument
        default:
            return nil
        }
    }
    
    var verificationDocuments: [SecureIdVerificationDocumentReference]? {
        switch self {
        case let .bankStatement(value):
            return value.verificationDocuments
        case let .rentalAgreement(value):
            return value.verificationDocuments
        case let .utilityBill(value):
            return value.verificationDocuments
        case let .passportRegistration(value):
            return value.verificationDocuments
        case let .temporaryRegistration(value):
            return value.verificationDocuments
        default:
            return nil
        }
    }
    
    var translations: [SecureIdVerificationDocumentReference]? {
        switch self {
        case let .passport(value):
            return value.translations
        case let .idCard(value):
            return value.translations
        case let .driversLicense(value):
            return value.translations
        case let .internalPassport(value):
            return value.translations
        case let .utilityBill(value):
            return value.translations
        case let .rentalAgreement(value):
            return value.translations
        case let .temporaryRegistration(value):
            return value.translations
        case let .passportRegistration(value):
            return value.translations
        case let .bankStatement(value):
            return value.translations
        default:
            return nil
        }
    }
    
    var frontSideVerificationDocument: SecureIdVerificationDocumentReference? {
        switch self {
        case let .idCard(value):
            return value.frontSideDocument
        case let .passport(value):
            return value.frontSideDocument
        case let .driversLicense(value):
            return value.frontSideDocument
        case let .internalPassport(value):
            return value.frontSideDocument
        default:
            return nil
        }
    }
    
    var backSideVerificationDocument: SecureIdVerificationDocumentReference? {
        switch self {
        case let .idCard(value):
            return value.backSideDocument
        case let .driversLicense(value):
            return value.backSideDocument
        default:
            return nil
        }
    }
    
    var hasBacksideDocument: Bool {
        switch self {
        case .idCard:
            return true
        case .driversLicense:
            return true
        default:
            return false
        }
    }
    
    var phoneValue: SecureIdPhoneValue? {
        switch self {
        case let .phone(value):
            return value
        default:
            return nil
        }
    }
    var emailValue: SecureIdEmailValue? {
        switch self {
        case let .email(value):
            return value
        default:
            return nil
        }
    }
    
    var requestFieldType: SecureIdRequestedFormFieldValue {
        return key.requestFieldType
    }
    
    var expiryDate: SecureIdDate? {
        switch self {
        case let .idCard(value):
            return value.expiryDate
        case let .passport(value):
            return value.expiryDate
        case let .driversLicense(value):
            return value.expiryDate
        default:
            return nil
        }
    }
}

public extension SecureIdValueKey {
    var requestFieldType: SecureIdRequestedFormFieldValue {
        switch self {
        case .address:
            return .address
        case .bankStatement:
            return .bankStatement(translation: true)
        case .driversLicense:
            return .driversLicense(selfie: true, translation: true)
        case .email:
            return .email
        case .idCard:
            return .idCard(selfie: true, translation: true)
        case .internalPassport:
            return .internalPassport(selfie: true, translation: true)
        case .passport:
            return .passport(selfie: true, translation: true)
        case .passportRegistration:
            return .passportRegistration(translation: true)
        case .personalDetails:
            return .personalDetails(nativeName: true)
        case .phone:
            return .phone
        case .rentalAgreement:
            return .rentalAgreement(translation: true)
        case .temporaryRegistration:
            return .temporaryRegistration(translation: true)
        case .utilityBill:
            return .utilityBill(translation: true)
        }
    }
}

public extension SecureIdRequestedFormFieldValue {
    var rawValue: String {
        switch self {
        case .email:
            return strings().secureIdRequestPermissionEmail
        case .phone:
            return strings().secureIdRequestPermissionPhone
        case .address:
            return strings().secureIdRequestPermissionResidentialAddress
        case .utilityBill:
            return strings().secureIdRequestPermissionUtilityBill
        case .bankStatement:
            return strings().secureIdRequestPermissionBankStatement
        case .rentalAgreement:
            return strings().secureIdRequestPermissionTenancyAgreement
        case .passport:
            return strings().secureIdRequestPermissionPassport
        case .idCard:
            return strings().secureIdRequestPermissionIDCard
        case .driversLicense:
            return strings().secureIdRequestPermissionDriversLicense
        case .personalDetails:
            return strings().secureIdRequestPermissionPersonalDetails
        case .internalPassport:
            return strings().secureIdRequestPermissionInternalPassport
        case .passportRegistration:
            return strings().secureIdRequestPermissionPassportRegistration
        case .temporaryRegistration:
            return strings().secureIdRequestPermissionTemporaryRegistration
        }
    }
    
    var uploadFrontTitleText: String {
        switch self {
        case .idCard:
            return strings().secureIdUploadFront
        case .driversLicense:
            return strings().secureIdUploadFront
        default:
            return strings().secureIdUploadMain
        }
    }
    var uploadBackTitleText: String {
        switch self {
        case .idCard:
            return strings().secureIdUploadReverse
        case .driversLicense:
            return strings().secureIdUploadReverse
        default:
            return strings().secureIdUploadMain
        }
    }
    
    var hasBacksideDocument: Bool {
        switch self {
        case .idCard:
            return true
        case .driversLicense:
            return true
        default:
            return false
        }
    }
    
    var hasSelfie: Bool {
        switch self {
        case let .passport(selfie, _), let .idCard(selfie, _), let .driversLicense(selfie, _), let .internalPassport(selfie, _):
            return selfie
        default:
            return false
        }
    }
    
    var hasTranslation: Bool {
        switch self {
        case let .passport(_, translation), let .idCard(_, translation), let .driversLicense(_, translation), let .internalPassport(_, translation):
            return translation
        case let .utilityBill(translation), let .rentalAgreement(translation), let .bankStatement(translation), let .passportRegistration(translation), let .temporaryRegistration(translation):
            return translation
        default:
            return false
        }
    }
    
    var emptyDescription: String {
        switch self {
        case .email:
            return strings().secureIdRequestPermissionEmailEmpty
        case .phone:
            return strings().secureIdRequestPermissionPhoneEmpty
        case .utilityBill:
            return strings().secureIdEmptyDescriptionUtilityBill
        case .bankStatement:
            return strings().secureIdEmptyDescriptionBankStatement
        case .rentalAgreement:
            return strings().secureIdEmptyDescriptionTenancyAgreement
        case .passportRegistration:
            return strings().secureIdEmptyDescriptionPassportRegistration
        case .temporaryRegistration:
            return strings().secureIdEmptyDescriptionTemporaryRegistration
        case .passport:
            return strings().secureIdEmptyDescriptionPassport
        case .driversLicense:
            return strings().secureIdEmptyDescriptionDriversLicense
        case .idCard:
            return strings().secureIdEmptyDescriptionIdentityCard
        case .internalPassport:
            return strings().secureIdEmptyDescriptionInternalPassport
        case .personalDetails:
            return strings().secureIdEmptyDescriptionPersonalDetails
        case .address:
            return strings().secureIdEmptyDescriptionAddress
        }
    }
    
    var descAdd: String {
        switch self {
        case .email:
            return ""
        case .phone:
            return ""
        case .address:
            return strings().secureIdAddResidentialAddress
        case .utilityBill:
            return strings().secureIdAddUtilityBill
        case .bankStatement:
            return strings().secureIdAddBankStatement
        case .rentalAgreement:
            return strings().secureIdAddTenancyAgreement
        case .passport:
            return strings().secureIdAddPassport
        case .idCard:
            return strings().secureIdAddID
        case .driversLicense:
            return strings().secureIdAddDriverLicense
        case .personalDetails:
            return strings().secureIdAddPersonalDetails
        case .internalPassport:
            return strings().secureIdAddInternalPassport
        case .passportRegistration:
            return strings().secureIdAddPassportRegistration
        case .temporaryRegistration:
            return strings().secureIdAddTemporaryRegistration
        }
    }
    
    var descEdit: String {
        switch self {
        case .email:
            return ""
        case .phone:
            return ""
        case .address:
            return strings().secureIdEditResidentialAddress
        case .utilityBill:
            return strings().secureIdEditUtilityBill
        case .bankStatement:
            return strings().secureIdEditBankStatement
        case .rentalAgreement:
            return strings().secureIdEditTenancyAgreement
        case .passport:
            return strings().secureIdEditPassport
        case .idCard:
            return strings().secureIdEditID
        case .driversLicense:
            return strings().secureIdEditDriverLicense
        case .personalDetails:
            return strings().secureIdEditPersonalDetails
        case .internalPassport:
            return strings().secureIdEditInternalPassport
        case .passportRegistration:
            return strings().secureIdEditPassportRegistration
        case .temporaryRegistration:
            return strings().secureIdEditTemporaryRegistration
        }
    }
}

public extension SecureIdRequestedFormFieldValue  {
    var valueKey: SecureIdValueKey {
        switch self {
        case .address:
            return .address
        case .bankStatement:
            return .bankStatement
        case .driversLicense:
            return .driversLicense
        case .email:
            return .email
        case .idCard:
            return .idCard
        case .passport:
            return .passport
        case .personalDetails:
            return .personalDetails
        case .phone:
            return .phone
        case .rentalAgreement:
            return .rentalAgreement
        case .utilityBill:
            return .utilityBill
        case .internalPassport:
            return .internalPassport
        case .passportRegistration:
            return .passportRegistration
        case .temporaryRegistration:
            return .temporaryRegistration
        }
    }
    
    var primary: SecureIdRequestedFormFieldValue {
        if SecureIdRequestedFormField.just(self).isIdentityField {
            return .personalDetails(nativeName: true)
        }
        if SecureIdRequestedFormField.just(self).isAddressField {
            return .address
        }
        return self
    }
    
    func isEqualToMRZ(_ mrz: TGPassportMRZ) -> Bool {
        switch mrz.documentType.lowercased() {
        case "p":
            if case .passport = self {
                return true
            } else {
                return false
            }
        default:
            return false
        }
    }
    
}


public extension SecureIdGender {
    var stringValue: String {
        switch self {
        case .female:
            return strings().secureIdGenderFemale
        case .male:
            return strings().secureIdGenderMale
        }
    }
}

public extension SecureIdDate {
    var stringValue: String {
        return "\(day).\(month).\(year)"
    }
}

public struct SecureIdDocumentValue {
    public let document: SecureIdVerificationDocument
    public let stableId: AnyHashable
    public let context: SecureIdAccessContext
    public init(document: SecureIdVerificationDocument, context: SecureIdAccessContext, stableId: AnyHashable) {
        self.document = document
        self.stableId = stableId
        self.context = context
    }
    public var image: TelegramMediaImage {
        return TelegramMediaImage(imageId: MediaId(namespace: 0, id: 0), representations: [TelegramMediaImageRepresentation(dimensions: PixelDimensions(100, 100), resource: document.resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
    }
}
