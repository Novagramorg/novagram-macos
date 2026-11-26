public struct SidebarLimits {
    public let dialog_filters_limit_default: Int
    public let dialog_filters_limit_premium: Int
    public let dialog_filters_chats_limit_default: Int
    public let dialog_filters_chats_limit_premium: Int
    public let community_invites_limit_default: Int
    public let community_invites_limit_premium: Int
    public let communities_joined_limit_default: Int
    public let communities_joined_limit_premium: Int

    public init(dialog_filters_limit_default: Int, dialog_filters_limit_premium: Int, dialog_filters_chats_limit_default: Int, dialog_filters_chats_limit_premium: Int, community_invites_limit_default: Int, community_invites_limit_premium: Int, communities_joined_limit_default: Int, communities_joined_limit_premium: Int) {
        self.dialog_filters_limit_default = dialog_filters_limit_default
        self.dialog_filters_limit_premium = dialog_filters_limit_premium
        self.dialog_filters_chats_limit_default = dialog_filters_chats_limit_default
        self.dialog_filters_chats_limit_premium = dialog_filters_chats_limit_premium
        self.community_invites_limit_default = community_invites_limit_default
        self.community_invites_limit_premium = community_invites_limit_premium
        self.communities_joined_limit_default = communities_joined_limit_default
        self.communities_joined_limit_premium = communities_joined_limit_premium
    }
}
