import Foundation

public struct ExportInfoRow {
    public let label: String
    public let value: String
    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct ExportListEntry {
    public let colorIndex: Int
    public let initials: String
    public let title: String
    public let subtitle: String?
    public let info: [String]
    public let href: String?
    public let photoSrc: String?
    public init(colorIndex: Int, initials: String, title: String, subtitle: String?, info: [String] = [], href: String? = nil, photoSrc: String? = nil) {
        self.colorIndex = colorIndex
        self.initials = initials
        self.title = title
        self.subtitle = subtitle
        self.info = info
        self.href = href
        self.photoSrc = photoSrc
    }
}

public struct ExportMenuItem {
    public let title: String
    public let counter: String?
    public let href: String
    public init(title: String, counter: String?, href: String) {
        self.title = title
        self.counter = counter
        self.href = href
    }
}

public struct ExportStoryGridItem {
    public let mediaSrc: String?
    public let thumbSrc: String?
    public let isVideo: Bool
    public let caption: String
    public let dateBadge: String
    public let colorIndex: Int
    public init(mediaSrc: String?, thumbSrc: String?, isVideo: Bool, caption: String, dateBadge: String, colorIndex: Int) {
        self.mediaSrc = mediaSrc
        self.thumbSrc = thumbSrc
        self.isVideo = isVideo
        self.caption = caption
        self.dateBadge = dateBadge
        self.colorIndex = colorIndex
    }
}

public struct ExportChatPaneItem {
    public let colorIndex: Int
    public let initials: String
    public let title: String
    public let subtitle: String?
    public let messagesHref: String
    public let photoSrc: String?
    public init(colorIndex: Int, initials: String, title: String, subtitle: String?, messagesHref: String, photoSrc: String?) {
        self.colorIndex = colorIndex
        self.initials = initials
        self.title = title
        self.subtitle = subtitle
        self.messagesHref = messagesHref
        self.photoSrc = photoSrc
    }
}

public final class ExportOverviewWriter {
    public let baseURL: URL
    private let themeColors: ExportThemeColors?

    public init(baseURL: URL, themeColors: ExportThemeColors? = nil) {
        self.baseURL = baseURL
        self.themeColors = themeColors
    }

    public func writeAssets() throws {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
        let cssDir = baseURL.appendingPathComponent("css")
        let jsDir = baseURL.appendingPathComponent("js")
        try FileManager.default.createDirectory(at: cssDir, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: jsDir, withIntermediateDirectories: true, attributes: nil)
        try (ChatExportHtmlWriter.styleCss(themeColors).data(using: .utf8) ?? Data()).write(to: cssDir.appendingPathComponent("style.css"))
        try (ChatExportHtmlWriter.scriptJs.data(using: .utf8) ?? Data()).write(to: jsDir.appendingPathComponent("script.js"))
    }

    // MARK: - Pages

    @discardableResult
    public func writeIndex(fileName: String, title: String, accountName: String?, accountAvatarSrc: String?, accountColorIndex: Int, accountInitials: String, menu: [ExportMenuItem], chatsHeader: String?, chats: [ExportListEntry]) -> String {
        var body = "<div class=\"sections\">\n"
        for item in menu {
            body += "<a class=\"section block_link\" href=\"\(esc(item.href))\">\n"
            if let counter = item.counter, !counter.isEmpty {
                body += "<div class=\"counter details\">\(esc(counter))</div>\n"
            }
            body += "<div class=\"label bold\">\(esc(item.title))</div>\n"
            body += "</a>\n"
        }
        body += "</div>\n"

        if !chats.isEmpty {
            if let header = chatsHeader, !header.isEmpty {
                body += "<div class=\"page_about details with_divider\">\(esc(header))</div>\n"
            }
            body += entryListHtml(chats)
        }

        var headerOverride: String?
        if let accountName = accountName, !accountName.isEmpty {
            let avatar: String
            if let src = accountAvatarSrc, !src.isEmpty {
                avatar = "<img class=\"userpic\" style=\"width: 44px; height: 44px\" src=\"\(esc(src))\"/>\n"
            } else {
                avatar = userpicHtml(colorIndex: accountColorIndex, initials: accountInitials, photoSrc: nil, size: 44)
            }
            headerOverride = "<div class=\"page_header chat_header\">\n<div class=\"content bubble\">\n\(avatar)<div class=\"body\">\n<div class=\"name bold\">\(esc(accountName))</div>\n<div class=\"subtitle details\">\(esc(title))</div>\n</div>\n</div>\n</div>"
        }

        write(fileName: fileName, title: title, backLink: nil, bodyClass: "list_page", body: body, headerOverride: headerOverride)
        return fileName
    }

    @discardableResult
    public func writePersonalInfo(fileName: String, title: String, name: String, colorIndex: Int, initials: String, photoSrcs: [String], rows: [ExportInfoRow]) -> String {
        var body = "<div class=\"personal_info clearfix\">\n"
        body += "<div class=\"pull_left userpic_wrap\">\n"
        if let main = photoSrcs.first {
            body += "<a class=\"photo_wrap\" href=\"\(esc(main))\">\n"
            body += "<img class=\"userpic\" style=\"width: 96px; height: 96px\" src=\"\(esc(main))\"/>\n"
            body += "</a>\n"
        } else {
            body += userpicHtml(colorIndex: colorIndex, initials: initials, photoSrc: nil, size: 96)
        }
        body += "</div>\n"
        body += "<div class=\"rows\">\n"
        for row in rows where !row.value.isEmpty {
            body += "<div class=\"row\">\n"
            body += "<div class=\"label details\">\(esc(row.label))</div>\n"
            body += "<div class=\"value bold\">\(escMultiline(row.value))</div>\n"
            body += "</div>\n"
        }
        body += "</div>\n"
        body += "</div>\n"

        if photoSrcs.count > 1 {
            body += "<div class=\"profile_photos\">\n"
            for src in photoSrcs.dropFirst() {
                body += "<a class=\"photo_wrap\" href=\"\(esc(src))\">\n"
                body += "<img class=\"profile_photo_thumb\" src=\"\(esc(src))\"/>\n"
                body += "</a>\n"
            }
            body += "</div>\n"
        }

        write(fileName: fileName, title: title, backLink: "export_results.html", bodyClass: nil, body: body)
        return fileName
    }

    @discardableResult
    public func writeListPage(fileName: String, title: String, about: String?, entries: [ExportListEntry]) -> String {
        var body = ""
        if let about = about, !about.isEmpty {
            body += "<div class=\"page_about details\">\(esc(about))</div>\n"
        }
        body += entryListHtml(entries)
        write(fileName: fileName, title: title, backLink: "export_results.html", bodyClass: "list_page", body: body)
        return fileName
    }

    @discardableResult
    public func writeStoriesGrid(fileName: String, title: String, about: String?, items: [ExportStoryGridItem]) -> String {
        var body = ""
        if let about = about, !about.isEmpty {
            body += "<div class=\"page_about details\">\(esc(about))</div>\n"
        }
        body += "<div class=\"stories_grid\">\n"
        for item in items {
            let dateBadge = item.dateBadge.isEmpty ? "" : "<div class=\"story_date_badge\">\(esc(item.dateBadge))</div>\n"
            let playOverlay = item.isVideo ? "<div class=\"story_play\"></div>\n" : ""
            if let media = item.mediaSrc {
                let thumb = item.thumbSrc ?? media
                let wrapClass = item.isVideo ? "video_file_wrap" : "photo_wrap"
                let captionAttr = item.caption.isEmpty ? "" : " data-caption=\"\(esc(item.caption))\""
                body += "<a class=\"story_cell \(wrapClass)\" href=\"\(esc(media))\"\(captionAttr)>\n"
                body += "<img class=\"story_thumb\" src=\"\(esc(thumb))\"/>\n"
                body += playOverlay
                body += dateBadge
                body += "</a>\n"
            } else if let thumb = item.thumbSrc {
                body += "<div class=\"story_cell\">\n"
                body += "<img class=\"story_thumb\" src=\"\(esc(thumb))\"/>\n"
                body += playOverlay
                body += dateBadge
                body += "</div>\n"
            } else {
                let bucket = (item.colorIndex % 8) + 1
                body += "<div class=\"story_cell story_placeholder userpic\(bucket)\">\n"
                body += "<div class=\"story_type\">\(esc(item.isVideo ? "Video" : "Photo"))</div>\n"
                if !item.dateBadge.isEmpty {
                    body += "<div class=\"story_date\">\(esc(item.dateBadge))</div>\n"
                }
                body += "</div>\n"
            }
        }
        body += "</div>\n"
        write(fileName: fileName, title: title, backLink: "export_results.html", bodyClass: "list_page", body: body)
        return fileName
    }

    @discardableResult
    public func writeChatsPane(fileName: String, title: String, chats: [ExportChatPaneItem]) -> String {
        var sidebar = "<div class=\"dialog_list\">\n"
        for (i, chat) in chats.enumerated() {
            let activeClass = i == 0 ? " active" : ""
            sidebar += "<a class=\"dialog clearfix\(activeClass)\" href=\"\(esc(chat.messagesHref))\" target=\"chat_frame\" data-src=\"\(esc(chat.messagesHref))\">\n"
            sidebar += "<div class=\"pull_left userpic_wrap\">\n"
            sidebar += userpicHtml(colorIndex: chat.colorIndex, initials: chat.initials, photoSrc: chat.photoSrc, size: 48)
            sidebar += "</div>\n"
            sidebar += "<div class=\"body\">\n"
            sidebar += "<div class=\"name bold\">\(esc(chat.title))</div>\n"
            if let subtitle = chat.subtitle, !subtitle.isEmpty {
                sidebar += "<div class=\"subname details\">\(esc(subtitle))</div>\n"
            }
            sidebar += "</div>\n"
            sidebar += "</a>\n"
        }
        sidebar += "</div>\n"

        let firstSrc = chats.first?.messagesHref ?? ""
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(esc(title))</title>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <link href="css/style.css" rel="stylesheet">
        </head>
        <body class="chats_body">
        <div class="chats_layout">
        <div class="chats_sidebar">
        <a class="chats_sidebar_header bold back_link" href="export_results.html">\(esc(title))</a>
        \(sidebar)</div>
        <div class="chat_pane">
        <iframe id="chat_frame" name="chat_frame" src="\(esc(firstSrc))"></iframe>
        </div>
        </div>
        <script>
        (function () {
            var frame = document.getElementById('chat_frame');
            var dialogs = document.querySelectorAll('.dialog');
            for (var i = 0; i < dialogs.length; i++) {
                dialogs[i].addEventListener('click', function (e) {
                    e.preventDefault();
                    var src = this.getAttribute('data-src');
                    if (src) { frame.src = src; }
                    for (var j = 0; j < dialogs.length; j++) { dialogs[j].classList.remove('active'); }
                    this.classList.add('active');
                });
            }
        })();
        </script>
        </body>
        </html>
        """
        let url = baseURL.appendingPathComponent(fileName)
        try? (html.data(using: .utf8) ?? Data()).write(to: url)
        return fileName
    }

    // MARK: - Building blocks

    private func entryListHtml(_ entries: [ExportListEntry]) -> String {
        var result = "<div class=\"entry_list\">\n"
        for entry in entries {
            let tag = entry.href != nil ? "a" : "div"
            let hrefAttr = entry.href.flatMap { " href=\"\(esc($0))\"" } ?? ""
            let extraClass = entry.href != nil ? " block_link" : ""
            result += "<\(tag) class=\"entry clearfix\(extraClass)\"\(hrefAttr)>\n"
            result += "<div class=\"pull_left userpic_wrap\">\n"
            result += userpicHtml(colorIndex: entry.colorIndex, initials: entry.initials, photoSrc: entry.photoSrc, size: 48)
            result += "</div>\n"
            result += "<div class=\"body\">\n"
            result += "<div class=\"name bold\">\(esc(entry.title))</div>\n"
            if let subtitle = entry.subtitle, !subtitle.isEmpty {
                result += "<div class=\"subname details\">\(esc(subtitle))</div>\n"
            }
            for line in entry.info where !line.isEmpty {
                result += "<div class=\"info details\">\(esc(line))</div>\n"
            }
            result += "</div>\n"
            result += "</\(tag)>\n"
        }
        result += "</div>\n"
        return result
    }

    private func userpicHtml(colorIndex: Int, initials: String, photoSrc: String?, size: Int) -> String {
        if let photoSrc = photoSrc, !photoSrc.isEmpty {
            return "<img class=\"userpic\" style=\"width: \(size)px; height: \(size)px\" src=\"\(esc(photoSrc))\"/>\n"
        }
        let bucket = (colorIndex % 8) + 1
        var result = "<div class=\"userpic userpic\(bucket)\" style=\"width: \(size)px; height: \(size)px\">\n"
        result += "<div class=\"initials\" style=\"line-height: \(size)px\">\(esc(initials))</div>\n"
        result += "</div>\n"
        return result
    }

    private func write(fileName: String, title: String, backLink: String?, bodyClass: String?, body: String, headerOverride: String? = nil) {
        let headerBlock: String
        if let headerOverride = headerOverride {
            headerBlock = headerOverride
        } else {
            let headerContent: String
            if let backLink = backLink {
                headerContent = "<a class=\"content\" href=\"\(esc(backLink))\">\n<div class=\"text bold\">\(esc(title))</div>\n</a>"
            } else {
                headerContent = "<div class=\"content\">\n<div class=\"text bold\">\(esc(title))</div>\n</div>"
            }
            headerBlock = "<div class=\"page_header\">\n\(headerContent)\n</div>"
        }
        let bodyClassAttr = bodyClass.map { " \($0)" } ?? ""
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(esc(title))</title>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <link href="css/style.css" rel="stylesheet">
        <script src="js/script.js" type="text/javascript"></script>
        </head>
        <body>
        <div class="page_wrap">
        \(headerBlock)
        <div class="page_body\(bodyClassAttr)">
        \(body)</div>
        </div>
        </body>
        </html>
        """
        let url = baseURL.appendingPathComponent(fileName)
        try? (html.data(using: .utf8) ?? Data()).write(to: url)
    }

    // MARK: - Escaping

    private func esc(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        return result
    }

    private func escMultiline(_ string: String) -> String {
        return esc(string).replacingOccurrences(of: "\n", with: "<br>")
    }
}
