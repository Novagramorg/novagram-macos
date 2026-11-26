import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI



public func reportComplicated(context: (any AccountContextProtocol), subject: ReportContentSubject, title: String) {
    
    _ = showModalProgress(signal: context.engine.messages.reportContent(subject: subject, option: nil, message: nil), for: context.window).start(next: { result in
        switch result {
        case .reported:
            showModalText(for: context.window, text: strings().chatMessageSponsoredReportSuccess)
        case let .options(titleInfo, options):
            showComplicatedReport(context: context, title: titleInfo, info: nil, header: title, data: .init(subject: .list(options.map { .init(string: $0.text, id: $0.option) }), title: strings().chatMessageSponsoredReportOptionTitle), report: { report in
                return context.engine.messages.reportContent(subject: subject, option: report.id, message: report.string) |> `catch` { error in
                    return .single(.reported)
                } |> deliverOnMainQueue |> map { result in
                    switch result {
                    case let .options(_, options):
                        return .init(subject: .list(options.map { .init(string: $0.text, id: $0.option) }), title: report.string)
                    case .reported:
                        showModalText(for: context.window, text: strings().chatMessageSponsoredReportSuccess)
                        return nil
                    case let .addComment(optional, option):
                        return .init(subject: .comment(optional: optional, id: option), title: report.string)
                    }
                }
            })
        case .addComment:
            break
        }
        
    })
    
}
