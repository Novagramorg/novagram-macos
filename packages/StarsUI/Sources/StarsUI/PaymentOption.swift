import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import TelegramMediaUtils
import TelegramMedia
import LocalAnimations
import CurrencyFormat
import PremiumStatusUI
import SceneEffects
import DustLayer
import InAppPurchaseManager
import ObjcUtils
import PremiumUI
import CalendarUtils
import DateUtils
import LokiRng
import FoundationUtils
import InputView
import InputTextView

public struct PaymentOption : Equatable {
    public var title: String
    public var desc: String
    public var total: String
    public var discount: String?
    public var months: Int32
    public init(title: String, desc: String, total: String, discount: String? = nil, months: Int32) {
        self.title = title
        self.desc = desc
        self.total = total
        self.discount = discount
        self.months = months
    }
}

public struct DefaultPrice : Equatable {
    public let intergal: Int64
    public let decimal: NSDecimalNumber
    public init(intergal: Int64, decimal: NSDecimalNumber) {
        self.intergal = intergal
        self.decimal = decimal
    }
}
