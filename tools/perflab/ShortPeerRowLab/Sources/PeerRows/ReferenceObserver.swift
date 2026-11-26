import Cocoa
import TGUIKit

class ReferenceObserverView: NSView, Notifable {
    var item: AnyObject?
    var received: [Int] = []
    func notify(with value: Any, oldValue: Any, animated: Bool) { received.append(value as! Int) }
    func isEqual(to other: Notifable) -> Bool { self === other }
    func set(_ item: ShortPeerRowItem) {
        let previousType = (self.item as? ShortPeerRowItem)?.interactionType ?? .plain
        switch previousType {
        case let .selectable(interaction, _):
            interaction.remove(observer: self)
        case .deletable:
            break
        default:
            break
        }

        self.item = item
        switch previousType {
        case let .selectable(interaction, _), let .interactable(interaction):
            interaction.add(observer: self)
        case .deletable:
            break
        default:
            break
        }

        viewDidMoveToSuperview()
    }
    open override func viewDidMoveToSuperview() {

        if let item = item as? ShortPeerRowItem {
            switch item.interactionType {
            case let .selectable(interaction, _), let .interactable(interaction):
                if superview == nil {
                    interaction.remove(observer: self)
                } else {
                    interaction.add(observer: self)
                }
            case .deletable:
                break
            default:
                break
            }
        }


    }

}
