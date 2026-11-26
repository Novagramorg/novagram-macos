import Foundation
import TelegramUtils
import InputView
import Postbox
import TelegramCore
import TelegramLinks

public enum ChatInitialAction : Equatable {
    case start(parameter: String, behavior: ChatInitialActionBehavior)
    case inputText(text: ChatTextInputState, behavior: ChatInitialActionBehavior)
    case files(list: [String], behavior: ChatInitialActionBehavior)
    case forward(messageIds: [MessageId], text: ChatTextInputState?, behavior: ChatInitialActionBehavior)
    case reply(EngineMessageReplySubject, behavior: ChatInitialActionBehavior)
    case ad(EngineChatList.AdditionalItem.PromoInfo.Content)
    case source(MessageId, Int32?)
    case closeAfter(Int32)
    case selectToReport(reason: ReportReasonValue)
    case joinVoiceChat(_ joinHash: String?)
    case attachBot(_ bot: String, _ payload: String?, _ choose:[String]?)
    case makeWebview(appname: String, command: String?)
    case openWebview(botPeer: PeerEquatable, botApp: BotApp, result: RequestWebViewResult)
    case album(album: Int32, mode: PeerMediaCollectionMode)
    case openMedia(_ timemark: Int32?)
    case openTopic(thread: ChatReplyThreadMessage)
    case pollOption(Data)
    case direct
}
