import Foundation
import Postbox
import TelegramCore

public let verifyCodePeerId = PeerId.init(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(489000))

public let servicePeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(777000))

public let prod_repliesPeerId: PeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(1271266957))
public let test_repliesPeerId: PeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(708513))
public var repliesPeerId: PeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(1271266957))
