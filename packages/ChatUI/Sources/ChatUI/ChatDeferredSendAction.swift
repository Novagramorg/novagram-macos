public final class ChatDeferredSendAction {
    private let isCurrent: () -> Bool
    private var consumed = false

    init(isCurrent: @escaping () -> Bool) {
        self.isCurrent = isCurrent
    }

    public var isAvailable: Bool {
        !consumed && isCurrent()
    }

    public func takeIfCurrent(onInvalidated: () -> Void = {}) -> Bool {
        guard !consumed else { return false }
        consumed = true
        guard isCurrent() else {
            onInvalidated()
            return false
        }
        return true
    }
}

func chatHasSameDeferredSendState(_ lhs: ChatPresentationInterfaceState, _ rhs: ChatPresentationInterfaceState) -> Bool {
    guard lhs.chatLocation == rhs.chatLocation,
          lhs.chatMode == rhs.chatMode,
          lhs.state == rhs.state,
          lhs.currentSendAsPeerId == rhs.currentSendAsPeerId,
          lhs.sendPaidMessageStars == rhs.sendPaidMessageStars,
          lhs.isMonoforum == rhs.isMonoforum,
          lhs.threadedBot == rhs.threadedBot,
          lhs.slowMode?.hasLocked == rhs.slowMode?.hasLocked,
          lhs.slowModeMultipleLocked == rhs.slowModeMultipleLocked,
          lhs.effectiveInput.inputText == rhs.effectiveInput.inputText,
          lhs.effectiveInput.attributes == rhs.effectiveInput.attributes else { return false }
    let left = lhs.interfaceState
    let right = rhs.interfaceState
    return left.editState == right.editState
        && left.replyMessageId == right.replyMessageId
        && left.replyMessage?.threadId == right.replyMessage?.threadId
        && left.forwardMessageIds == right.forwardMessageIds
        && left.hideSendersName == right.hideSendersName
        && left.hideCaptions == right.hideCaptions
        && left.composeDisableUrlPreview == right.composeDisableUrlPreview
        && left.linkBelowMessage == right.linkBelowMessage
        && left.largeMedia == right.largeMedia
        && left.messageEffect == right.messageEffect
        && left.suggestPost == right.suggestPost
}
