import Cocoa

public let simpleDif: Int32 = 10 * 60

public enum ForwardItemType {
    case FullHeader;
    case ShortHeader;
    case Inside;
    case Bottom;
}

public enum AdminBadgeType: Equatable {
    case none
    case admin
    case owner
}

public enum ChatItemType : Equatable {

    public enum Header {
        case normal
        case short
    }

    case Full(rank: String?, rankType: AdminBadgeType, header: Header)
    case Short(rank: String?, rankType: AdminBadgeType, header: Header)
}
