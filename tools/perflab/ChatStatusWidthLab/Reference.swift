import Cocoa

public struct ReferenceFrames {
        public private(set) var state:NSRect?
        public private(set) var read:NSRect?
        public private(set) var sending:NSRect?
        public private(set) var reactions: NSRect?
        public private(set) var replyCount: NSRect?
        public private(set) var replyImage: NSRect?
        public private(set) var viewsCount: NSRect?
        public private(set) var viewsImage: NSRect?
        public private(set) var postAuthor: NSRect?
        public private(set) var pin: NSRect?
        public private(set) var edit: NSRect?
        public private(set) var paidMessageCount: NSRect?
        public private(set) var paidMessageImage: NSRect?
        public private(set) var diceStakeCount: NSRect?
        public private(set) var diceStakeImage: NSRect?
        public private(set) var date: NSRect?
        public private(set) var failed: NSRect?
        public private(set) var effect: NSRect?
        private let isStateOverlay: Bool
        public init(_ item: ChatRowItem, size: NSSize) {

            self.isStateOverlay = item.isStateOverlayLayout
            let stateIsEnd = item.isBubbled && !item.isIncoming

            var x: CGFloat = item.isStateOverlayLayout ? 4 : 0

            if let _ = item.messageEffect {
                var rect = size.bounds.focus(NSMakeSize(14, 14))
                rect.origin.x = x + 2
                rect.origin.y += 1
                self.effect = rect
                x = rect.maxX
            }

            if let views = item.replyCount {
                var rect_i = size.bounds.focus(item.presentation.chat.repliesCountIcon(item).backingSize)
                rect_i.origin.x = x + 2
                if item.isBubbled {
                    rect_i.origin.y -= 1
                }
                x = rect_i.maxX
                var rect_t = size.bounds.focus(views.layoutSize)
                rect_t.origin.x = x + 2
                x = rect_t.maxX

                self.replyImage = rect_i
                self.replyCount = rect_t
            }

            if item.isPinned {
                var rect = size.bounds.focus(item.presentation.chat.messagePinnedIcon(item).backingSize)
                rect.origin.x = x + 2
                self.pin = rect
                x = rect.maxX
            }

            if let views = item.channelViews {
                var rect_i = size.bounds.focus(item.presentation.chat.channelViewsIcon(item).backingSize)
                rect_i.origin.x = x + 2
                x = rect_i.maxX
                var rect_t = size.bounds.focus(views.layoutSize)
                rect_t.origin.x = x + 2
                x = rect_t.maxX

                self.viewsImage = rect_i
                self.viewsCount = rect_t
            }

            if let postAuthor = item.postAuthor {
                var rect = size.bounds.focus(postAuthor.layoutSize)
                rect.origin.x = x + 2
                self.postAuthor = rect
                x = rect.maxX
            }

            if let editLabel = item.editedLabel {
                var rect = size.bounds.focus(editLabel.layoutSize)
                rect.origin.x = x + 2
                self.edit = rect
                x = rect.maxX
            }

            if let paidMessage = item.paidMessage {
                var rect_i = size.bounds.focus(item.presentation.chat.paidMessageIcon(item).backingSize)
                rect_i.origin.x = x + 2
                rect_i.origin.y -= 1
                x = rect_i.maxX
                var rect_t = size.bounds.focus(paidMessage.layoutSize)
                rect_t.origin.x = x + 2
                x = rect_t.maxX

                self.paidMessageImage = rect_i
                self.paidMessageCount = rect_t
            }

            if item.isFailed {
                var rect = size.bounds.focus(item.presentation.icons.sentFailed.backingSize)
                rect.origin.x = x + 2
                self.failed = rect
                x = rect.maxX
            }

            if stateIsEnd {
                self.date = makeDate(item, size, &x)
            }

            self.state = makeState(item, size, &x)
            self.read = makeRead(item, size, &x)
            self.sending = makeSending(item, size, &x)

            if !stateIsEnd {
                if self.read == nil && (self.state != nil || self.sending != nil)  {
                    x += 4
                }
                self.date = makeDate(item, size, &x)
            }

            if let diceStake = item.diceStake {
                var rect_i = size.bounds.focus(item.presentation.chat.diceStakeIcon(item).backingSize)
                rect_i.origin.x = x + 2
                rect_i.origin.y -= 1
                x = rect_i.maxX
                var rect_t = size.bounds.focus(diceStake.layoutSize)
                rect_t.origin.x = x
                x = rect_t.maxX

                self.diceStakeImage = rect_i
                self.diceStakeCount = rect_t
            }
        }

        private func makeDate(_ item: ChatRowItem, _ size: NSSize, _ x: inout CGFloat) -> NSRect? {
            if let date = item.date {
                var rect = size.bounds.focus(date.layoutSize)
                rect.origin.x = x + 2
                x = rect.maxX
                return rect
            }
            return nil
        }

        private func makeState(_ item: ChatRowItem, _ size: NSSize, _ x: inout CGFloat) -> CGRect? {
            let hasState = !item.isIncoming && !item.isUnsent && !item.isFailed && !item.chatInteraction.isLogInteraction
            if hasState {
                var rect = size.bounds.focus(item.presentation.chat.stateStateIcon(item).backingSize)
                rect.origin.x = x + 2
                x = rect.maxX
                return rect
            }
            return nil
        }
        private func makeRead(_ item: ChatRowItem, _ size: NSSize, _ x: inout CGFloat) -> CGRect? {
            let hasState = !item.isIncoming && !item.isUnsent && !item.isFailed && !item.chatInteraction.isLogInteraction
            let hasRead = hasState && item.isRead && !item.hasSource
            if hasRead {
                var rect = size.bounds.focus(item.presentation.chat.readStateIcon(item).backingSize)
                rect.origin.x = x - 8
                x = rect.maxX
                return rect
            }
            return nil
        }
        private func makeSending(_ item: ChatRowItem, _ size: NSSize, _ x: inout CGFloat) -> CGRect? {
            let isSending = item.isUnsent && !item.isFailed
            if isSending {
                var rect = size.bounds.focus(NSMakeSize(12, 12))
                rect.origin.x = x + 2
                if isStateOverlay {
                    if System.backingScale > 1 {
                        rect.origin.y -= 0.5
                    }
                    rect.origin.x += 1
                }
                x = rect.maxX
                return rect
            }
            return nil
        }

        public var width: CGFloat {
            let rects = [self.state,
                         self.read,
                         self.sending,
                         self.effect,
                         self.diceStakeCount,
                         self.diceStakeImage,
                         self.paidMessageCount,
                         self.paidMessageImage,
                         self.replyCount,
                         self.viewsCount,
                         self.viewsImage,
                         self.postAuthor,
                         self.pin,
                         self.edit,
                         self.date].compactMap { $0 }

            var max = rects.max(by: { $0.maxX < $1.maxX }) ?? .zero
            if max == self.state || max == self.sending {
                max.origin.x += 4
            }
            if isStateOverlay {
                return max.maxX + 4
            } else {
                return max.maxX + 1
            }

        }
    }
