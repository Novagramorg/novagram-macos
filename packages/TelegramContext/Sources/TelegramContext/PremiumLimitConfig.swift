import Foundation
import TelegramCore
import InAppSettings

public final class PremiumBuyConfig {
    public let botUsername: String?
    public let invoiceSlug: String?
    public init(appConfiguration: AppConfiguration) {
        self.botUsername = appConfiguration.data?["premium_bot_username"] as? String
        self.invoiceSlug = appConfiguration.data?["premium_invoice_slug"] as? String
    }
}

public final class PremiumPromoOrder {
    public private(set) var premiumValues:[PremiumValue] = []
    public init(appConfiguration: AppConfiguration) {
        if let data = appConfiguration.data {
            if let order = data["premium_promo_order"] as? [String] {
                premiumValues = order.compactMap { PremiumValue(rawValue: $0) }
            }
            if let order = data["business_promo_order"] as? [String] {
                premiumValues.append(contentsOf: order.compactMap { PremiumValue(rawValue: $0) })
            }
            
            #if DEBUG
            premiumValues.append(.rich_formatting)
            #endif
        }
    }
}

public final class PremiumLimitConfig {
    public let channels_limit_default: Int
    public let channels_limit_premium: Int
    
    public let channels_public_limit_default: Int
    public let channels_public_limit_premium: Int
    
    public let saved_gifs_limit_default: Int
    public let saved_gifs_limit_premium: Int
    
    public let stickers_faved_limit_default: Int
    public let stickers_faved_limit_premium: Int
    
    public let dialog_filters_limit_default: Int
    public let dialog_filters_limit_premium: Int
    
    public let dialog_filters_chats_limit_default: Int
    public let dialog_filters_chats_limit_premium: Int
    
    public let dialog_filters_pinned_limit_default: Int
    public let dialog_filters_pinned_limit_premium: Int
    
    
    public let dialog_pinned_limit_default: Int
    public let dialog_pinned_limit_premium: Int

    public let caption_length_limit_default: Int
    public let caption_length_limit_premium: Int
    
    public let upload_max_fileparts_default: Int
    public let upload_max_fileparts_premium: Int
    
    public let dialogs_folder_pinned_limit_default: Int
    public let dialogs_folder_pinned_limit_premium: Int

    
    public let about_length_limit_default: Int
    public let about_length_limit_premium: Int
    
    public let premium_purchase_blocked: Bool
    public let show_premium_gift_in_attach_menu: Bool
    
    public let community_invites_limit_default: Int
    public let community_invites_limit_premium: Int

    public let communities_joined_limit_default: Int
    public let communities_joined_limit_premium: Int

    
    public init(appConfiguration: AppConfiguration) {
        if let data = appConfiguration.data {
            self.channels_limit_default = Int(data["channels_limit_default"] as? Double ?? 500)
            self.channels_limit_premium = Int(data["channels_limit_premium"] as? Double ?? 1000)

            self.channels_public_limit_default = Int(data["channels_public_limit_default"] as? Double ?? 5)
            self.channels_public_limit_premium = Int(data["channels_public_limit_premium"] as? Double ?? 10)

            self.saved_gifs_limit_default = Int(data["saved_gifs_limit_default"] as? Double ?? 25)
            self.saved_gifs_limit_premium = Int(data["saved_gifs_limit_premium"] as? Double ?? 200)

            self.stickers_faved_limit_default = Int(data["stickers_faved_limit_default"] as? Double ?? 5)
            self.stickers_faved_limit_premium = Int(data["stickers_faved_limit_premium"] as? Double ?? 200)

            self.dialog_filters_limit_default = Int(data["dialog_filters_limit_default"] as? Double ?? 10)
            self.dialog_filters_limit_premium = Int(data["dialog_filters_limit_premium"] as? Double ?? 20)

            self.dialog_filters_chats_limit_default = Int(data["dialog_filters_chats_limit_default"] as? Double ?? 100)
            self.dialog_filters_chats_limit_premium = Int(data["dialog_filters_chats_limit_premium"] as? Double ?? 200)

            self.dialog_filters_pinned_limit_default = Int(data["dialog_filters_chats_limit_default"] as? Double ?? 100)
            self.dialog_filters_pinned_limit_premium = Int(data["dialog_filters_chats_limit_premium"] as? Double ?? 200)

            self.dialog_pinned_limit_default = Int(data["dialog_pinned_limit_default"] as? Double ?? 5)
            self.dialog_pinned_limit_premium =  Int(data["dialog_pinned_limit_premium"] as? Double ?? 10)
            
            self.caption_length_limit_default = Int(data["caption_length_limit_default"] as? Double ?? 1024)
            self.caption_length_limit_premium = Int(data["caption_length_limit_premium"] as? Double ?? 2048)
            
            self.upload_max_fileparts_default = Int(data["upload_max_fileparts_default"] as? Double ?? 4000) / 2 * 1024 * 1024
            self.upload_max_fileparts_premium = Int(data["upload_max_fileparts_premium"] as? Double ?? 8000) / 2 * 1024 * 1024

            self.dialogs_folder_pinned_limit_default = Int(data["dialogs_folder_pinned_limit_default"] as? Double ?? 100)
            self.dialogs_folder_pinned_limit_premium = Int(data["dialogs_folder_pinned_limit_premium"] as? Double ?? 200)

            self.about_length_limit_default = Int(data["about_length_limit_default"] as? Double ?? 70)
            self.about_length_limit_premium = Int(data["about_length_limit_premium"] as? Double ?? 140)
            
            self.premium_purchase_blocked = data["premium_purchase_blocked"] as? Bool ?? true
            self.show_premium_gift_in_attach_menu = data["premium_gift_attach_menu_icon"] as? Bool ?? false
            
            self.community_invites_limit_default = Int(data["community_invites_limit_default"] as? Double ?? 3)
            self.community_invites_limit_premium = Int(data["community_invites_limit_premium"] as? Double ?? 100)

            self.communities_joined_limit_default = Int(data["communities_joined_limit_default"] as? Double ?? 2)
            self.communities_joined_limit_premium = Int(data["communities_joined_limit_premium"] as? Double ?? 20)

        } else {
            self.channels_limit_default = 500
            self.channels_limit_premium = 1000

            self.channels_public_limit_default = 5
            self.channels_public_limit_premium = 10

            self.saved_gifs_limit_default = 25
            self.saved_gifs_limit_premium = 200

            self.stickers_faved_limit_default = 5
            self.stickers_faved_limit_premium = 200
            
            self.dialog_filters_limit_default = 10
            self.dialog_filters_limit_premium = 20

            self.dialog_filters_chats_limit_default = 100
            self.dialog_filters_chats_limit_premium = 200

            self.dialog_filters_pinned_limit_default = 100
            self.dialog_filters_pinned_limit_premium = 200
            
            self.dialog_pinned_limit_default = 5
            self.dialog_pinned_limit_premium = 10
            
            self.caption_length_limit_default = 1024
            self.caption_length_limit_premium = 2048
            
            self.upload_max_fileparts_default = 4000 / 2 * 1024 * 1024
            self.upload_max_fileparts_premium = 8000 / 2 * 1024 * 1024
            
            self.dialogs_folder_pinned_limit_default = 100
            self.dialogs_folder_pinned_limit_premium = 200
            
            self.about_length_limit_default = 70
            self.about_length_limit_premium = 140
            
            self.premium_purchase_blocked = true
            self.show_premium_gift_in_attach_menu = false
            
            self.community_invites_limit_default = 3
            self.community_invites_limit_premium = 100

            self.communities_joined_limit_default = 2
            self.communities_joined_limit_premium = 20


        }
    }
}
