import Foundation

public struct ExportThemeColors {
    public let background: String
    public let text: String
    public let secondaryText: String
    public let accent: String
    public let link: String
    public let surface: String
    public let border: String
    public init(background: String, text: String, secondaryText: String, accent: String, link: String, surface: String, border: String) {
        self.background = background
        self.text = text
        self.secondaryText = secondaryText
        self.accent = accent
        self.link = link
        self.surface = surface
        self.border = border
    }
}

extension ChatExportHtmlWriter {
    static func styleCss(_ colors: ExportThemeColors?) -> String {
        var css = baseStyleCss + "\n" + overrideCss
        if let colors = colors {
            css += "\n" + themeCss(colors)
        }
        css += "\n" + modernCss(accent: colors?.accent ?? "#4098f0")
        return css
    }

    static func themeCss(_ c: ExportThemeColors) -> String {
        return """
        html, body { background-color: \(c.background); }
        .page_wrap { background-color: \(c.background); color: \(c.text); }
        .page_wrap a { color: \(c.link); }
        .page_body { background-color: \(c.background); }
        .page_header { background-color: \(c.background); border-bottom: 1px solid \(c.border); }
        .bold { color: \(c.text); }
        .details { color: \(c.secondaryText); }
        .with_divider { border-top: 1px solid \(c.border); }
        .message { color: \(c.text); }
        .list_page .entry { color: \(c.text); }
        .default .from_name { color: \(c.accent); }
        .default .media .description { color: \(c.text); }
        .default:hover { background-color: \(c.surface); }
        pre, .text pre { background-color: \(c.surface); color: \(c.text); border: 1px solid \(c.border); }
        code, .text code { background-color: \(c.surface); color: \(c.accent); }
        .text blockquote { border-left: 3px solid \(c.accent); }
        .reactions .reaction { background-color: \(c.surface); color: \(c.accent); }
        .service .body { background-color: \(c.surface); color: \(c.text); }
        .spoiler { background: \(c.surface); }
        .chats_body, .chats_sidebar, .chats_sidebar_header { background-color: \(c.background); }
        .chats_sidebar { border-right: 1px solid \(c.border); }
        .chats_sidebar_header { border-bottom: 1px solid \(c.border); }
        .dialog:hover, .dialog.active { background-color: \(c.surface); }
        .page_header.chat_header .content.bubble { background-color: \(c.surface); border: 1px solid \(c.border); }
        .scroll_down_btn { background-color: \(c.surface); border: 1px solid \(c.border); color: \(c.text); }
        .webpage_preview { border-left-color: \(c.accent); }
        """
    }

    static func modernCss(accent: String) -> String {
        return """
        .page_body {
            width: 820px;
            max-width: 94%;
            padding-top: 104px;
            padding-bottom: 48px;
        }
        .page_header {
            background: transparent !important;
            background-color: transparent !important;
            border-bottom: none !important;
            pointer-events: none;
            padding: 14px 0;
        }
        .page_header .content {
            pointer-events: auto;
            box-sizing: border-box;
            display: block;
            width: max-content;
            max-width: 92%;
            margin: 0 auto;
            background-color: rgba(130, 130, 130, 0.15);
            border: 1px solid rgba(130, 130, 130, 0.16);
            border-radius: 30px !important;
            box-shadow: 0 6px 24px rgba(0, 0, 0, 0.20);
            -webkit-backdrop-filter: blur(20px);
            backdrop-filter: blur(20px);
        }
        .page_header .content .text {
            padding: 13px 26px !important;
            font-size: 17px !important;
        }
        .page_header a.content .text {
            padding: 13px 26px 13px 46px !important;
        }
        .page_header a.content::before {
            left: 24px !important;
            top: 50% !important;
            margin-top: -5px;
        }
        .page_header.chat_header .content.bubble {
            background-color: rgba(130, 130, 130, 0.15) !important;
            border: 1px solid rgba(130, 130, 130, 0.16) !important;
            box-shadow: 0 6px 24px rgba(0, 0, 0, 0.20);
            -webkit-backdrop-filter: blur(20px);
            backdrop-filter: blur(20px);
        }
        .sections,
        .entry_list,
        .personal_info {
            background-color: rgba(130, 130, 130, 0.08);
            border: 1px solid rgba(130, 130, 130, 0.13);
            border-radius: 18px;
            margin-top: 4px;
            overflow: hidden;
        }
        .sections,
        .entry_list {
            padding: 4px 0 !important;
        }
        .section {
            height: auto !important;
            padding: 12px 22px !important;
            display: flex;
            flex-direction: column-reverse;
            align-items: flex-start;
            background-image: none !important;
            position: relative;
        }
        .section .label {
            padding: 0 !important;
            font-size: 15px;
        }
        .section .counter {
            float: none !important;
            padding: 3px 0 0 0 !important;
            font-size: 13px;
        }
        .section:not(:last-child)::after {
            content: '';
            position: absolute;
            left: 22px; right: 0; bottom: 0; height: 1px;
            background-color: rgba(130, 130, 130, 0.14);
        }
        .list_page .entry {
            padding: 9px 18px !important;
            position: relative;
            overflow: hidden;
        }
        .list_page .entry .name {
            font-size: 15px;
        }
        .list_page .entry:not(:last-child)::after {
            content: '';
            position: absolute;
            left: 78px; right: 0; bottom: 0; height: 1px;
            background-color: rgba(130, 130, 130, 0.13);
        }
        a.block_link:hover {
            background-color: rgba(130, 130, 130, 0.10);
        }
        .personal_info {
            padding: 22px;
        }
        .profile_photos {
            background-color: rgba(130, 130, 130, 0.08);
            border: 1px solid rgba(130, 130, 130, 0.13);
            border-radius: 18px;
            margin-top: 12px;
            padding: 18px 20px !important;
        }
        .chats_body {
            background-color: transparent;
        }
        .chats_layout {
            box-sizing: border-box;
            height: 100vh;
            padding: 12px;
            gap: 12px;
        }
        .chats_sidebar {
            position: relative;
            width: 340px;
            min-width: 340px;
            height: calc(100vh - 24px);
            border: 1px solid rgba(130, 130, 130, 0.16) !important;
            border-radius: 16px;
            background-color: rgba(130, 130, 130, 0.08);
            overflow: hidden;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.14);
        }
        .chats_sidebar_header {
            position: absolute !important;
            top: 10px;
            left: 0;
            right: 0;
            z-index: 5;
            width: max-content;
            max-width: calc(100% - 20px);
            box-sizing: border-box;
            margin: 0 auto !important;
            padding: 12px 22px 12px 46px !important;
            font-size: 17px;
            background-color: rgba(120, 120, 120, 0.28) !important;
            border: 1px solid rgba(130, 130, 130, 0.16) !important;
            border-bottom: 1px solid rgba(130, 130, 130, 0.16) !important;
            border-radius: 24px !important;
            box-shadow: 0 4px 16px rgba(0, 0, 0, 0.22);
            -webkit-backdrop-filter: blur(22px);
            backdrop-filter: blur(22px);
        }
        .chats_sidebar_header.back_link::before {
            left: 24px !important;
            top: 50% !important;
            margin-top: -5px !important;
        }
        .dialog_list {
            height: 100%;
            box-sizing: border-box;
            overflow-y: auto;
            padding: 68px 10px 10px 10px;
        }
        .chat_pane {
            height: calc(100vh - 24px);
            border: 1px solid rgba(130, 130, 130, 0.16);
            border-radius: 16px;
            overflow: hidden;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.14);
        }
        #chat_frame {
            border-radius: 16px;
        }
        .dialog {
            margin: 3px 0;
            padding: 9px 10px;
            border-radius: 12px;
        }
        .dialog:hover {
            background-color: rgba(130, 130, 130, 0.10);
        }
        .dialog.active {
            background-color: \(accent);
        }
        .dialog.active .name,
        .dialog.active .subname {
            color: #ffffff !important;
        }
        """
    }

    private static let overrideCss = #"""
/* self-contained export overrides */
.chat_page .photo,
.chat_page .video_file,
.chat_page .animated,
.chat_page .sticker {
    max-width: 320px;
    max-height: 320px;
}
.chat_page .media .thumb {
    object-fit: cover;
}
.default .media .fill,
.default .media .thumb {
    border-radius: 8px;
}
.chat_page .default .text {
    padding-top: 2px;
}
.chat_page .forwarded_from,
.chat_page .reply_to,
.chat_page .signature {
    padding-bottom: 5px;
}

/* modern look */
body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    font-size: 14px;
    line-height: 1.45;
}
.page_body {
    width: 640px;
    max-width: 92%;
}
.default {
    padding: 6px 12px;
    border-radius: 10px;
}
.default:hover {
    background-color: rgba(127, 127, 127, 0.07);
}
.default .from_name {
    font-size: 14px;
    padding-bottom: 1px;
}
.default .text {
    font-size: 14px;
    line-height: 1.5;
}
.default .body {
    margin-left: 56px;
}
.userpic .initials {
    font-weight: 600;
}
.pull_right.date {
    font-weight: 400;
    opacity: 0.75;
}
.text h1, .text h2, .text h3, .text h4, .text h5, .text h6 {
    margin: 8px 0 4px;
    line-height: 1.3;
}
.text p {
    margin: 6px 0;
}
.text ul, .text ol {
    margin: 6px 0;
    padding-left: 24px;
}
.text li {
    margin: 2px 0;
}
.text pre {
    background: rgba(127, 127, 127, 0.12);
    padding: 8px 12px;
    border-radius: 4px;
    overflow-x: auto;
    white-space: pre-wrap;
}
.text code {
    background: rgba(127, 127, 127, 0.12);
    padding: 1px 4px;
    border-radius: 3px;
}
.text blockquote {
    border-left: 3px solid #3892db;
    margin: 6px 0;
    padding: 2px 0 2px 12px;
}
.text table {
    border-collapse: collapse;
    margin: 6px 0;
}
.text th, .text td {
    border: 1px solid rgba(127, 127, 127, 0.4);
    padding: 4px 8px;
    text-align: left;
}
.text hr {
    border: none;
    border-top: 1px solid rgba(127, 127, 127, 0.3);
    margin: 8px 0;
}
.text details {
    margin: 6px 0;
}
.text summary {
    cursor: pointer;
    font-weight: 700;
}

/* lightbox gallery */
.photo_wrap, .sticker_wrap, .video_file_wrap, .animated_wrap {
    cursor: zoom-in;
}
.lightbox {
    display: none;
    position: fixed;
    top: 0; left: 0; right: 0; bottom: 0;
    background: rgba(0, 0, 0, 0.92);
    z-index: 1000;
    align-items: center;
    justify-content: center;
}
.lightbox.shown {
    display: flex;
}
.lightbox_content {
    max-width: 94%;
    max-height: 94%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
}
.lightbox_caption {
    color: #fff;
    margin-top: 14px;
    max-width: 720px;
    max-height: 22vh;
    overflow-y: auto;
    text-align: center;
    font-size: 15px;
    line-height: 1.4;
    white-space: pre-wrap;
    word-wrap: break-word;
}
.lightbox_media {
    max-width: 100%;
    max-height: 94vh;
    border-radius: 6px;
    box-shadow: 0 10px 50px rgba(0, 0, 0, 0.6);
}
.lightbox_close {
    position: absolute;
    top: 12px; right: 22px;
    color: #fff;
    font-size: 42px;
    line-height: 1;
    cursor: pointer;
    opacity: 0.8;
    user-select: none;
}
.lightbox_close:hover {
    opacity: 1;
}
.lightbox_prev, .lightbox_next {
    position: absolute;
    top: 50%;
    transform: translateY(-50%);
    color: #fff;
    font-size: 56px;
    line-height: 1;
    cursor: pointer;
    opacity: 0.55;
    user-select: none;
    padding: 20px;
}
.lightbox_prev { left: 6px; }
.lightbox_next { right: 6px; }
.lightbox_prev:hover, .lightbox_next:hover {
    opacity: 1;
}

/* back arrow on sub-page headers (Stories, Contacts, Personal info, Sessions) */
.page_header a.content {
    position: relative;
    color: inherit;
    text-decoration: none !important;
}
.page_header a.content::before {
    content: '';
    position: absolute;
    left: 32px;
    top: 50%;
    width: 10px;
    height: 10px;
    margin-top: -5px;
    border-left: 2px solid currentColor;
    border-bottom: 2px solid currentColor;
    transform: rotate(45deg);
    opacity: 0.85;
}

/* personal info: gap between avatar and rows + clickable profile-photo gallery */
.personal_info .pull_left.userpic_wrap {
    margin-right: 24px;
}
.personal_info .userpic_wrap a.photo_wrap {
    display: block;
    cursor: zoom-in;
}
.profile_photos {
    padding: 0 24px 20px 24px;
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
}
.profile_photos a.photo_wrap {
    display: block;
    cursor: zoom-in;
}
.profile_photos .profile_photo_thumb {
    width: 64px;
    height: 64px;
    border-radius: 50%;
    object-fit: cover;
    display: block;
}

/* scroll-to-bottom button (chat pages) */
.scroll_down_btn {
    position: fixed;
    right: 24px;
    bottom: 24px;
    width: 48px;
    height: 48px;
    border-radius: 50%;
    background-color: #ffffff;
    border: 1px solid #e3e6e8;
    color: #707579;
    box-shadow: 0 2px 12px rgba(0, 0, 0, 0.18);
    cursor: pointer;
    opacity: 0;
    pointer-events: none;
    transition: opacity 0.2s ease;
    z-index: 500;
}
.scroll_down_btn.shown {
    opacity: 1;
    pointer-events: auto;
}
.scroll_down_arrow {
    position: absolute;
    left: 50%;
    top: 50%;
    width: 12px;
    height: 12px;
    margin: -9px 0 0 -6px;
    border-right: 2px solid currentColor;
    border-bottom: 2px solid currentColor;
    transform: rotate(45deg);
}
@media (prefers-color-scheme: dark) {
    .scroll_down_btn {
        background-color: #2c333d;
        border: 1px solid #3a424d;
        color: #ffffff;
    }
}

/* webpage link preview card */
.webpage_preview {
    display: block;
    border-left: 3px solid #3892db;
    padding: 3px 0 4px 12px;
    margin: 5px 0;
    text-decoration: none !important;
    color: inherit;
    overflow: hidden;
    border-radius: 0 4px 4px 0;
}
.webpage_preview:hover {
    background-color: rgba(127, 127, 127, 0.06);
}
.webpage_photo {
    width: 64px;
    height: 64px;
    object-fit: cover;
    border-radius: 8px;
    margin-left: 12px;
    margin-bottom: 4px;
}
.webpage_site {
    font-weight: 600;
    padding-bottom: 1px;
}
.webpage_title {
    padding-bottom: 1px;
}
.webpage_description {
    white-space: pre-wrap;
    word-wrap: break-word;
}

/* stories grid */
.stories_grid {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    padding: 32px 24px 24px 24px;
}
.stories_grid .story_cell {
    position: relative;
    width: 160px;
    height: 160px;
    border-radius: 10px;
    overflow: hidden;
    display: block;
}
.stories_grid a.story_cell {
    cursor: zoom-in;
}
.stories_grid .story_thumb {
    width: 160px;
    height: 160px;
    object-fit: cover;
    display: block;
}
.stories_grid .story_placeholder {
    width: 160px;
    height: 160px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    text-align: center;
    color: #fff;
}
.stories_grid .story_placeholder .story_type {
    font-weight: 600;
    margin-bottom: 4px;
}
.stories_grid .story_play {
    position: absolute;
    left: 50%;
    top: 50%;
    width: 44px;
    height: 44px;
    margin: -22px 0 0 -22px;
    border-radius: 50%;
    background: rgba(0, 0, 0, 0.45);
    pointer-events: none;
}
.stories_grid .story_play::after {
    content: '';
    position: absolute;
    left: 17px;
    top: 13px;
    border-style: solid;
    border-width: 9px 0 9px 15px;
    border-color: transparent transparent transparent #fff;
}
.stories_grid .story_date_badge {
    position: absolute;
    left: 8px;
    bottom: 8px;
    color: #fff;
    font-size: 11px;
    padding: 2px 6px;
    border-radius: 6px;
    background: rgba(0, 0, 0, 0.5);
    pointer-events: none;
}

/* full-export chats: two-pane dialogs + chat view */
.chats_body {
    margin: 0;
    padding: 0;
    overflow: hidden;
    background-color: #ffffff;
}
.chats_layout {
    display: flex;
    height: 100vh;
    width: 100%;
}
.chats_sidebar {
    width: 320px;
    min-width: 320px;
    height: 100vh;
    overflow-y: auto;
    box-sizing: border-box;
    background-color: #ffffff;
    border-right: 1px solid #e3e6e8;
}
.chats_sidebar_header {
    padding: 18px 20px 14px 20px;
    font-size: 20px;
    position: sticky;
    top: 0;
    z-index: 1;
    background-color: #ffffff;
    border-bottom: 1px solid #e3e6e8;
}
.chats_sidebar_header.back_link {
    display: block;
    position: relative;
    padding-left: 46px;
    text-decoration: none !important;
}
.chats_sidebar_header.back_link::before {
    content: '';
    position: absolute;
    left: 22px;
    top: 24px;
    width: 10px;
    height: 10px;
    border-left: 2px solid currentColor;
    border-bottom: 2px solid currentColor;
    transform: rotate(45deg);
    opacity: 0.85;
}
.dialog {
    display: block;
    padding: 8px 14px;
    text-decoration: none !important;
    cursor: pointer;
}
.dialog:hover {
    background-color: rgba(127, 127, 127, 0.08);
}
.dialog.active {
    background-color: rgba(127, 127, 127, 0.16);
}
.dialog .userpic_wrap {
    margin-right: 12px;
}
.dialog .body {
    overflow: hidden;
}
.dialog .name {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
.dialog .subname {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    margin-top: 1px;
}
.chat_pane {
    flex: 1;
    height: 100vh;
    min-width: 0;
}
#chat_frame {
    width: 100%;
    height: 100%;
    border: none;
    display: block;
}
@media (prefers-color-scheme: dark) {
    .chats_body,
    .chats_sidebar,
    .chats_sidebar_header {
        background-color: #1a2026;
    }
    .chats_sidebar {
        border-right: 1px solid #2c333d;
    }
    .chats_sidebar_header {
        border-bottom: 1px solid #2c333d;
    }
}

/* floating chat header bubble */
.page_header.chat_header {
    background: none;
    background-color: transparent;
    border-bottom: none;
    pointer-events: none;
    padding: 10px 0;
}
.page_header.chat_header .content.bubble {
    pointer-events: auto;
    display: flex;
    align-items: center;
    box-sizing: border-box;
    width: max-content;
    max-width: 92%;
    margin: 0 auto;
    padding: 7px 22px 7px 7px;
    border-radius: 34px !important;
    background-color: #ffffff;
    border: 1px solid rgba(0, 0, 0, 0.08);
    box-shadow: 0 6px 22px rgba(0, 0, 0, 0.14);
    -webkit-backdrop-filter: blur(20px);
    backdrop-filter: blur(20px);
}
.page_header.chat_header .content.bubble .userpic {
    flex-shrink: 0;
}
.page_header.chat_header .content.bubble .body {
    margin-left: 12px;
    min-width: 0;
    text-align: left;
}
.page_header.chat_header .content.bubble .name {
    font-size: 15px;
    line-height: 18px;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
.page_header.chat_header .content.bubble .subtitle {
    font-size: 13px;
    line-height: 16px;
    margin-top: 1px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
.page_body.chat_page {
    padding-top: 84px;
}
@media (prefers-color-scheme: dark) {
    .page_header.chat_header .content.bubble {
        background-color: #232c36;
        border: 1px solid rgba(255, 255, 255, 0.08);
        box-shadow: 0 6px 22px rgba(0, 0, 0, 0.32);
    }
}
"""#

    private static let baseStyleCss = #"""
body {
    margin: 0;
    font: 12px/18px 'Open Sans',"Lucida Grande","Lucida Sans Unicode",Arial,Helvetica,Verdana,sans-serif;
}
strong {
    font-weight: 700;
}
code, kbd, pre, samp {
    font-family: Menlo,Monaco,Consolas,"Courier New",monospace;
}
code {
    padding: 2px 4px;
    font-size: 90%;
    color: #c7254e;
    background-color: #f9f2f4;
    border-radius: 4px;
}
pre {
    display: block;
    margin: 0;
    line-height: 1.42857143;
    word-break: break-all;
    word-wrap: break-word;
    color: #333;
    background-color: #f5f5f5;
    border-radius: 4px;
    overflow: auto;
    padding: 3px;
    border: 1px solid #eee;
    max-height: none;
    font-size: inherit;
}
.clearfix:after {
    content: " ";
    visibility: hidden;
    display: block;
    height: 0;
    clear: both;
}
.pull_left {
    float: left;
}
.pull_right {
    float: right;
}
.page_wrap {
    background-color: #ffffff;
    color: #000000;
}
.page_wrap a {
    color: #168acd;
    text-decoration: none;
}
.page_wrap a:hover {
    text-decoration: underline;
}
.page_header {
    position: fixed;
    z-index: 10;
    background-color: #ffffff;
    width: 100%;
    border-bottom: 1px solid #e3e6e8;
}
.page_header .content {
    width: 480px;
    margin: 0 auto;
    border-radius: 0 !important;
}
.page_header a.content {
    background-repeat: no-repeat;
    background-position: 24px 21px;
    background-size: 24px 24px;
}
.bold {
    color: #212121;
    font-weight: 700;
}
.details {
    color: #70777b;
}
.page_header .content .text {
    padding: 24px 24px 22px 24px;
    font-size: 22px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}
.page_header a.content .text {
    padding: 24px 24px 22px 82px;
}
.page_body {
    padding-top: 64px;
    width: 480px;
    margin: 0 auto;
}
.page_about {
    padding: 24px 24px;
}
.with_divider {
    border-top: 1px solid #e3e6e8;
}
.userpic_link {
    display: block;
    text-decoration: none;
}
.userpic_link:hover {
    text-decoration: none;
}
.userpic {
    display: block;
    border-radius: 50%;
    overflow: hidden;
}
.story {
    display: block;
    border-radius: 4px;
    overflow: hidden;
}
.userpic .initials {
    display: block;
    color: #fff;
    text-align: center;
    text-transform: uppercase;
    user-select: none;
}
.color_red,
.userpic1,
.media_call .fill,
.media_file .fill,
.media_live_location .fill {
    background-color: #ff5555;
}
.color_green,
.userpic2,
.media_call.success .fill,
.media_photo .fill {
    background-color: #64bf47;
}
.color_yellow,
.userpic3,
.media_venue .fill {
    background-color: #ffab00;
}
.color_blue,
.userpic4,
.media_audio_file .fill,
.media_voice_message .fill {
    background-color: #4f9cd9;
}
.color_purple,
.userpic5,
.media_game .fill {
    background-color: #9884e8;
}
.color_pink,
.userpic6,
.media_invoice .fill {
    background-color: #e671a5;
}
.color_sea,
.userpic7,
.media_location .fill,
.media_video .fill {
    background-color: #47bcd1;
}
.color_orange,
.userpic8,
.media_contact .fill {
    background-color: #ff8c44;
}
.personal_info {
    padding: 24px;
}
.personal_info .userpic .initials {
    font-size: 30px;
}
.personal_info .rows {
    float: left;
    padding-right: 24px;
}
.personal_info .names {
    width: 164px;
}
.personal_info .info {
    width: 124px;
}
.personal_info .bio {
    width: 400px;
}
.personal_info .row {
    padding-bottom: 16px;
}
a.block_link {
    display: block;
    text-decoration: none !important;
    border-radius: 4px;
}
a.block_link:hover {
    text-decoration: none !important;
    background-color: #f5f7f8;
}
a.expanded {
    padding: 2px 8px;
    margin: -2px -8px;
}
.sections {
    padding: 11px 0;
}
.section {
    height: 48px;
    background-position: 24px 12px;
    background-repeat: no-repeat;
    background-size: 24px 24px;
}
.section .counter {
    float: right;
    padding: 14px 24px 0;
    font-size: 15px;
}
.section .label {
    padding: 15px 0 0 82px;
    font-size: 15px;
}
.list_page .page_about {
    padding: 16px 24px 0;
    font-size: 11px;
}
.list_page .entry_list {
    padding: 16px 0;
}
.list_page .entry {
    padding: 10px 16px;
}
.list_page .entry .userpic .initials {
    font-size: 18px;
}
.list_page .entry .body {
    margin-left: 66px;
}
.list_page .entry .name {
    padding: 4px 0 2px;
    font-size: 14px;
}
.list_page .entry .subname {
    padding-top: 4px;
}
.list_page .entry .details_entry {
    padding-top: 4px;
}
.list_page .entry .info {
    font-size: 11px;
    padding-top: 5px;
}
.history {
    padding: 16px 0;
}
.message {
    margin: 0 -10px;
    transition: background-color 2.0s ease;
}
div.selected {
    background-color: rgba(242,246,250,255);
    transition: background-color 0.5s ease;
}
.service {
    padding: 10px 24px;
}
.service .body {
    text-align: center;
}
.service .userpic_wrap {
    padding-top: 10px;
}
.service .userpic {
    margin: 0 auto;
}
.service .userpic .initials {
    font-size: 24px;
}
.message .userpic .initials {
    font-size: 16px;
}
.default {
    padding: 10px;
}
.default.joined {
    margin-top: -10px;
}
.default .from_name {
    color: #3892db;
    font-weight: 700;
    padding-bottom: 5px;
}
.default .from_name .details {
    font-weight: normal;
}
.default .body {
    margin-left: 60px;
}
.default .text {
    word-wrap: break-word;
    line-height: 150%;
    unicode-bidi: plaintext;
    text-align: start;
}
.default .reply_to,
.default .media_wrap {
    padding-bottom: 5px;
}
.default .media {
    margin: 0 -10px;
    padding: 5px 10px;
}
.default .media .fill,
.default .media .thumb {
    width: 48px;
    height: 48px;
    border-radius: 50%;
}
.default .media .fill {
    background-repeat: no-repeat;
    background-position: 12px 12px;
    background-size: 24px 24px;
}
.default .media .title,
.default .media_poll .question {
    padding-top: 4px;
    font-size: 14px;
}
.default .media .description {
    color: #000000;
    padding-top: 4px;
    font-size: 13px;
}
.default .media .status {
    padding-top: 4px;
    font-size: 13px;
}
.default .video_file_wrap,
.default .animated_wrap {
    position: relative;
}
.default .video_file,
.default .animated,
.default .photo,
.default .sticker {
    display: block;
}
.video_duration {
    background: rgba(0, 0, 0, .4);
    padding: 0px 5px;
    position: absolute;
    z-index: 2;
    border-radius: 2px;
    right: 3px;
    bottom: 3px;
    color: #ffffff;
    font-size: 11px;
}
.video_play_bg {
    background: rgba(0, 0, 0, .4);
    width: 40px;
    height: 40px;
    line-height: 0;
    position: absolute;
    z-index: 2;
    border-radius: 50%;
    overflow: hidden;
    margin: -20px auto 0 -20px;
    top: 50%;
    left: 50%;
    pointer-events: none;
}
.video_play {
    position: absolute;
    display: inline-block;
    top: 50%;
    left: 50%;
    margin-left: -5px;
    margin-top: -9px;
    z-index: 1;
    width: 0;
    height: 0;
    border-style: solid;
    border-width: 9px 0 9px 14px;
    border-color: transparent transparent transparent #fff;
}
.gif_play {
    font-weight: 700;
    color: #FFF;
    display: block;
    line-height: 40px;
    font-size: 13px;
    text-align: center;
}
.pagination {
    text-align: center;
    padding: 20px;
    font-size: 16px;
}

.toast_container {
    position: fixed;
    left: 50%;
    top: 50%;
    opacity: 0;
    transition: opacity 3.0s ease;
}
.toast_body {
    margin: 0 -50%;
    float: left;
    border-radius: 15px;
    padding: 10px 20px;
    background: rgba(0, 0, 0, 0.7);
    color: #ffffff;
}
div.toast_shown {
    opacity: 1;
    transition: opacity 0.4s ease;
}

.page_header a.content {
    background-image: url(images/back.png);
}
.audio_icon {
    width: 48px;
    height: 48px;
    border-radius: 50%;
    background-color: #4f9cd9;
    background-repeat: no-repeat;
    background-position: 12px 12px;
    background-size: 24px 24px;
}

.spoiler {
    background: #e8e8e8;
}
.spoiler.hidden {
    background: #a9a9a9;
    cursor: pointer;
    border-radius: 3px;
}
.spoiler.hidden span {
    opacity: 0;
    user-select: none;
}

.bot_buttons_table {
    border-spacing: 0px 2px;
    width: 100%;
}
.bot_button {
    border-radius: 8px;
    text-align: center;
    vertical-align: middle;
    background-color: #168acd40;
}
.bot_button_row {
    display: table;
    table-layout: fixed;
    padding: 0px;
    width:100%;
}
.bot_button_row div {
    display: table-cell;
}
.bot_button_column_separator {
    width: 2px
}

.reactions {
    margin: 5px 0;
}

.reactions .reaction {
    display: inline-flex;
    height: 20px;
    border-radius: 15px;
    background-color: #e8f5fc;
    color: #168acd;
    font-weight: bold;
    margin-bottom: 5px;
}

.reactions .reaction.active {
    background-color: #40a6e2;
    color: #fff;
}

.reactions .reaction.paid {
    background-color: #fdf6e1;
    color: #c58523;
}

.reactions .reaction.active.paid {
    background-color: #ecae0a;
    color: #fdf6e1;
}

.reactions .reaction .emoji {
    line-height: 20px;
    margin: 0 5px;
    font-size: 15px;
}

.reactions .reaction .userpic:not(:first-child) {
    margin-left: -8px;
}

.reactions .reaction .userpic {
    display: inline-block;
}

.reactions .reaction .userpic .initials {
    font-size: 8px;
}

.reactions .reaction .count {
    margin-right: 8px;
    line-height: 20px;
}

@media (prefers-color-scheme: dark) {
html, body {
    background-color: #1a2026;
    margin: 0;
    padding: 0;
}
.page_wrap {
    background-color: #1a2026;
    color: #ffffff;
    min-height: 100vh;
}
.page_wrap a {
    color: #4db8ff;
}
.page_header {
    background-color: #1a2026;
    border-bottom: 1px solid #2c333d;
}
.bold {
    color: #ffffff;
}
.details {
    color: #91979e;
}
.page_body {
    background-color: #1a2026;
}
code {
    color: #ff8aac;
    background-color: #2c333d;
}
pre {
    color: #ffffff;
    background-color: #2c333d;
    border: 1px solid #323a45;
}
.with_divider {
    border-top: 1px solid #2c333d;
}
a.block_link:hover {
    background-color: #323a45;
}
.list_page .entry {
    color: #ffffff;
}
.message {
    color: #ffffff;
}
div.selected {
    background-color: #323a45;
}
.default .from_name {
    color: #4db8ff;
}
.default .media .description {
    color: #ffffff;
}
.spoiler {
    background: #323a45;
}
.spoiler.hidden {
    background: #61c0ff;
}
.bot_button {
    background-color: #4db8ff40;
}
.reactions .reaction {
    background-color: #2c333d;
    color: #4db8ff;
}
.reactions .reaction.active {
    background-color: #4db8ff;
    color: #1a2026;
}
.reactions .reaction.paid {
    background-color: #323a45;
    color: #febb5b;
}
.reactions .reaction.active.paid {
    background-color: #febb5b;
    color: #1a2026;
}
}
"""#

    static let scriptJs: String = baseScriptJs + "\n" + lightboxJs

    private static let baseScriptJs = #"""
"use strict";

window.AllowBackFromHistory = false;
function CheckLocation() {
    var start = "#go_to_message";
    var hash = location.hash;
    if (hash.substr(0, start.length) == start) {
        var messageId = parseInt(hash.substr(start.length));
        if (messageId) {
            GoToMessage(messageId);
        }
    } else if (hash == "#allow_back") {
        window.AllowBackFromHistory = true;
    } else {
        ScrollToBottom();
    }
}

function ScrollToBottom() {
    var html = document.documentElement;
    if (html) {
        html.scrollTop = html.scrollHeight;
    } else if (document.body) {
        window.scrollTo(0, document.body.scrollHeight);
    }
}

function ShowToast(text) {
    var container = document.createElement("div");
    container.className = "toast_container";
    var inner = container.appendChild(document.createElement("div"));
    inner.className = "toast_body";
    inner.appendChild(document.createTextNode(text));
    var appended = document.body.appendChild(container);
    setTimeout(function () {
        AddClass(appended, "toast_shown");
        setTimeout(function () {
            RemoveClass(appended, "toast_shown");
            setTimeout(function () {
                document.body.removeChild(appended);
            }, 3000);
        }, 3000);
    }, 0);
}

function ShowHashtag(tag) {
    ShowToast("This is a hashtag '#" + tag + "' link.");
    return false;
}

function ShowCashtag(tag) {
    ShowToast("This is a cashtag '$" + tag + "' link.");
    return false;
}

function ShowBotCommand(command) {
    ShowToast("This is a bot command '/" + command + "' link.");
    return false;
}

function ShowMentionName() {
    ShowToast("This is a link to a user mentioned by name.");
    return false;
}

function ShowNotLoadedEmoji() {
    ShowToast("This custom emoji is not included, change data exporting settings to download.");
    return false;
}

function ShowNotAvailableEmoji() {
    ShowToast("This custom emoji is not available.");
    return false;
}

function ShowTextCopied(content) {
    navigator.clipboard.writeText(content);
    ShowToast("Text copied to clipboard.");
    return false;
}

function ShowSpoiler(target) {
    if (target.classList.contains("hidden")) {
        target.classList.toggle("hidden");
    }
}

function AddClass(element, name) {
    var current = element.className;
    var expression = new RegExp('(^|\\s)' + name + '(\\s|$)', 'g');
    if (expression.test(current)) {
        return;
    }
    element.className = current + ' ' + name;
}

function RemoveClass(element, name) {
    var current = element.className;
    var expression = new RegExp('(^|\\s)' + name + '(\\s|$)', '');
    var match = expression.exec(current);
    while ((match = expression.exec(current)) != null) {
        if (match[1].length > 0 && match[2].length > 0) {
            current = current.substr(0, match.index + match[1].length)
                + current.substr(match.index + match[0].length);
        } else {
            current = current.substr(0, match.index)
                + current.substr(match.index + match[0].length);
        }
    }
    element.className = current;
}

function EaseOutQuad(t) {
    return t * t;
}

function EaseInOutQuad(t) {
    return (t < 0.5) ? (2 * t * t) : ((4 - 2 * t) * t - 1);
}

function ScrollHeight() {
    if ("innerHeight" in window) {
        return window.innerHeight;
    } else if (document.documentElement) {
        return document.documentElement.clientHeight;
    }
    return document.body.clientHeight;
}

function ScrollTo(top, callback) {
    var html = document.documentElement;
    var current = html.scrollTop;
    var delta = top - current;
    var finish = function () {
        html.scrollTop = top;
        if (callback) {
            callback();
        }
    };
    if (!window.performance.now || delta == 0) {
        finish();
        return;
    }
    var transition = EaseOutQuad;
    var max = 300;
    if (delta < -max) {
        current = top + max;
        delta = -max;
    } else if (delta > max) {
        current = top - max;
        delta = max;
    } else {
        transition = EaseInOutQuad;
    }
    var duration = 150;
    var interval = 7;
    var time = window.performance.now();
    var animate = function () {
        var now = window.performance.now();
        if (now >= time + duration) {
            finish();
            return;
        }
        var dt = (now - time) / duration;
        html.scrollTop = Math.round(current + delta * transition(dt));
        setTimeout(animate, interval);
    };
    setTimeout(animate, interval);
}

function ScrollToElement(element, callback) {
    var header = document.getElementsByClassName("page_header")[0];
    var headerHeight = header.offsetHeight;
    var html = document.documentElement;
    var scrollHeight = ScrollHeight();
    var available = scrollHeight - headerHeight;
    var padding = 10;
    var top = element.offsetTop;
    var height = element.offsetHeight;
    var desired = top
        - Math.max((available - height) / 2, padding)
        - headerHeight;
    var scrollTopMax = html.offsetHeight - scrollHeight;
    ScrollTo(Math.min(desired, scrollTopMax), callback);
}

function GoToMessage(messageId) {
    var element = document.getElementById("message" + messageId);
    if (element) {
        var hash = "#go_to_message" + messageId;
        if (location.hash != hash) {
            location.hash = hash;
        }
        ScrollToElement(element, function () {
            AddClass(element, "selected");
            setTimeout(function () {
                RemoveClass(element, "selected");
            }, 1000);
        });
    } else {
        ShowToast("This message was not exported. Maybe it was deleted.");
    }
    return false;
}

function GoBack(anchor) {
    if (!window.AllowBackFromHistory) {
        return true;
    }
    history.back();
    if (!anchor || !anchor.getAttribute) {
        return true;
    }
    var destination = anchor.getAttribute("href");
    if (!destination) {
        return true;
    }
    setTimeout(function () {
        location.href = destination;
    }, 100);
    return false;
}
"""#

    private static let lightboxJs = #"""
(function () {
    var selector = 'a.photo_wrap, a.sticker_wrap, a.video_file_wrap, a.animated_wrap';
    var overlay = null, contentEl = null, prevEl = null, nextEl = null;
    var items = [], current = -1;

    function isVideo(href) {
        return /\.(mp4|webm|mov|m4v|ogv)(\?.*)?$/i.test(href);
    }

    function collectItems() {
        items = [];
        var links = document.querySelectorAll(selector);
        for (var i = 0; i < links.length; i++) {
            var href = links[i].getAttribute('href');
            if (href) {
                items.push({ href: href, caption: links[i].getAttribute('data-caption') || '' });
            }
        }
    }

    function ensureOverlay() {
        if (overlay) {
            return;
        }
        overlay = document.createElement('div');
        overlay.className = 'lightbox';
        overlay.innerHTML = '<div class="lightbox_close">&times;</div>'
            + '<div class="lightbox_prev">&#8249;</div>'
            + '<div class="lightbox_next">&#8250;</div>'
            + '<div class="lightbox_content"></div>';
        document.body.appendChild(overlay);
        contentEl = overlay.querySelector('.lightbox_content');
        prevEl = overlay.querySelector('.lightbox_prev');
        nextEl = overlay.querySelector('.lightbox_next');
        overlay.addEventListener('click', function (e) {
            if (e.target === overlay || e.target === contentEl) {
                closeLightbox();
            }
        });
        overlay.querySelector('.lightbox_close').addEventListener('click', function (e) {
            e.stopPropagation();
            closeLightbox();
        });
        prevEl.addEventListener('click', function (e) {
            e.stopPropagation();
            show(current - 1);
        });
        nextEl.addEventListener('click', function (e) {
            e.stopPropagation();
            show(current + 1);
        });
    }

    function show(i) {
        if (!items.length) {
            return;
        }
        if (i < 0) {
            i = items.length - 1;
        }
        if (i >= items.length) {
            i = 0;
        }
        current = i;
        var href = items[i].href;
        var caption = items[i].caption;
        contentEl.innerHTML = '';
        var el;
        if (isVideo(href)) {
            el = document.createElement('video');
            el.src = href;
            el.controls = true;
            el.autoplay = true;
            el.loop = true;
        } else {
            el = document.createElement('img');
            el.src = href;
        }
        el.className = 'lightbox_media';
        contentEl.appendChild(el);
        if (caption) {
            var cap = document.createElement('div');
            cap.className = 'lightbox_caption';
            cap.textContent = caption;
            contentEl.appendChild(cap);
        }
        var many = items.length > 1;
        prevEl.style.display = many ? '' : 'none';
        nextEl.style.display = many ? '' : 'none';
    }

    function openLightbox(href) {
        collectItems();
        var i = -1;
        for (var k = 0; k < items.length; k++) {
            if (items[k].href === href) {
                i = k;
                break;
            }
        }
        if (i < 0) {
            items = [{ href: href, caption: '' }];
            i = 0;
        }
        ensureOverlay();
        overlay.classList.add('shown');
        document.body.style.overflow = 'hidden';
        show(i);
    }

    function closeLightbox() {
        if (!overlay) {
            return;
        }
        overlay.classList.remove('shown');
        contentEl.innerHTML = '';
        document.body.style.overflow = '';
    }

    document.addEventListener('click', function (e) {
        var target = e.target;
        var link = null;
        while (target && target !== document.body) {
            if (target.tagName === 'A' && /(photo_wrap|sticker_wrap|video_file_wrap|animated_wrap)/.test(target.className)) {
                link = target;
                break;
            }
            target = target.parentNode;
        }
        if (!link) {
            return;
        }
        var href = link.getAttribute('href');
        if (!href) {
            return;
        }
        e.preventDefault();
        openLightbox(href);
    });

    document.addEventListener('keydown', function (e) {
        if (!overlay || !overlay.classList.contains('shown')) {
            return;
        }
        if (e.key === 'Escape' || e.keyCode === 27) {
            closeLightbox();
        } else if (e.key === 'ArrowLeft' || e.keyCode === 37) {
            show(current - 1);
        } else if (e.key === 'ArrowRight' || e.keyCode === 39) {
            show(current + 1);
        }
    });

    document.addEventListener('DOMContentLoaded', function () {
        var allLinks = document.querySelectorAll('a[href]');
        for (var li = 0; li < allLinks.length; li++) {
            var lhref = allLinks[li].getAttribute('href') || '';
            if (/^(https?:|tg:|mailto:)/i.test(lhref)) {
                allLinks[li].setAttribute('target', '_blank');
                allLinks[li].setAttribute('rel', 'noopener noreferrer');
            }
        }
    });

    document.addEventListener('DOMContentLoaded', function () {
        if (!document.querySelector('.chat_page')) {
            return;
        }
        var btn = document.createElement('div');
        btn.className = 'scroll_down_btn';
        btn.innerHTML = '<div class="scroll_down_arrow"></div>';
        document.body.appendChild(btn);
        btn.addEventListener('click', function () {
            var target = document.documentElement.scrollHeight || document.body.scrollHeight;
            try {
                window.scrollTo({ top: target, behavior: 'smooth' });
            } catch (e) {
                window.scrollTo(0, target);
            }
        });
        function updateVisibility() {
            var pos = window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0;
            var full = document.documentElement.scrollHeight || document.body.scrollHeight;
            var maxScroll = full - window.innerHeight;
            if (maxScroll - pos > 200) {
                btn.classList.add('shown');
            } else {
                btn.classList.remove('shown');
            }
        }
        window.addEventListener('scroll', updateVisibility);
        window.addEventListener('resize', updateVisibility);
        updateVisibility();
    });
})();
"""#
}
