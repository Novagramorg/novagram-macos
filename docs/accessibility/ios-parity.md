# VoiceOver: iOS parity spec

Source of truth: `submodules/telegram-ios` (paths below are relative to `submodules/telegram-ios/submodules/`).
English texts are from `Telegram/Telegram-iOS/en.lproj/Localizable.strings` (this path is relative to the telegram-ios root). Swift accessor `strings.VoiceOver_Chat_Photo` = key `"VoiceOver.Chat.Photo"`.
`\n` below means a literal newline in the composed string (VoiceOver pauses on it).

## 1. Chat list row

`ChatListUI/Sources/Node/ChatListItem.swift`. The row node is one element (`isAccessibilityElement = true`, :1753). Label and value are pushed to the view on every apply (:5471-5472). No traits are set (neither ChatListItem.swift nor ListViewItemNode sets any).

**accessibilityLabel** (:1503-1535)
| Content | Composition |
|---|---|
| Peer | `<title>` + (`"\n" + VoiceOver.Chat.UnreadMessages(n)` if `combinedReadState.count > 0`) |
| Saved Messages (own peer) | `"DialogList.SavedMessages"` = "Saved Messages" in place of the title |
| Archive (group reference) | `"ChatList.ArchivedChatsTitle"` = "Archived Chats" + (`"\n" + VoiceOver.Chat.UnreadMessages(n)` if unread > 0) |
| Loading placeholder | nil |

`<title>` = `chatOrMonoforumMainPeer.displayTitle` (user's name order). `VoiceOver.Chat.UnreadMessages` is plural: "%@ unread message(s)".

**accessibilityValue** (:1537-1605): parts are joined by `\n`, in this order:
1. `"VoiceOver.ChatList.Message"` = "Message" when the last message is incoming, else `"VoiceOver.ChatList.OutgoingMessage"` = "Outgoing Message".
2. Only when incoming, the author is a user and `chatListItemStrings` did not hide the author (groups): `"VoiceOver.ChatList.MessageFrom"` = "From: %@" (author displayTitle).
3. Only when outgoing and read by the peer (`isOutgoingMessageIndexRead`): `"VoiceOver.ChatList.MessageRead"` = "Read".
4. Preview text: the `messageText` from `chatListItemStrings(...)` (`ChatListUI/Sources/Node/ChatListItemStrings.swift`). It is the same text the row shows: media names such as `"Message.Photo"`="Photo", `"Message.Video"`="Video", `"Message.Animation"`="GIF", `"Message.Audio"`="Voice Message", `"Message.VideoMessage"`="Video Message", `"Message.Location"`/`"Message.LiveLocation"`, `"Message.Contact"`, `"Message.File"`/file name, `"Message.Sticker"`/`"Message.StickerText"`="Sticker %@", plus service-message text from `plainServiceMessageString`. The archive row uses `richTextPreview` plain text when it has one.
- No messages: `"VoiceOver.ChatList.MessageEmpty"` = "Empty".
- Archive row with no message: comma-joined `compactDisplayTitle` of the archived peers.

**Not exposed on the row:** time/date, muted, pinned, verified/premium/scam badges, online dot, typing/draft text, mention/reaction badges, story ring. A draft or typing state never reaches the value, because `chatListItemStrings` only gets the messages.

**accessibilityCustomActions** (:4071-4077, assigned :5474-5480, performed :5844-5848 via `revealOptionSelected`). The actions are the swipe options, left options first and then right options. Each action's name is the option title.
- Left options, root list only (`leftRevealOptions`, :874-913): `"DialogList.Read"`="Read" when unread, else `"DialogList.Unread"`="Unread" (not for communities, and no mark-unread for forums). Then `"DialogList.Pin"`="Pin" / `"DialogList.Unpin"`="Unpin" when not editing.
- Right options (`revealOptions`, :746-802):
  - Saved-messages chats list: Pin/Unpin.
  - Archive: Pin/Unpin.
  - Otherwise: `"ChatList.Mute"`="Mute" / `"ChatList.Unmute"`="Unmute".
  - Then `"Common.Delete"`="Delete" if the chat can be deleted.
  - Then `"ChatList.ArchiveAction"`="Archive" (root list, or a filter that excludes archived) or `"ChatList.UnarchiveAction"`="Unarchive" (inside the archive).
- Archive row (`groupReferenceRevealOptions`, :804): `"ChatList.HideAction"`="Hide" / `"ChatList.UnhideAction"`="Pin".
- Forum topics (:816, :848): Mute/Unmute, `"Common.Delete"`, `"ChatList.CloseAction"`="Close" / `"ChatList.StartAction"`="Start", and Hide/Unhide.
- Custom lists (:4010-4024): Read/Unread, Mute/Unmute, then Delete or `"ChatList.Remove"`="Remove".

**Related**
- Filter tabs (`TelegramUI/Components/ChatList/ChatListFilterTabContainerNode/Sources/ChatListFilterTabContainerNode.swift:235-246`): label = folder title, value = `VoiceOver.Chat.UnreadMessages(n)` (or ""), traits `.button` plus `.selected` on the active tab.
- Back button: `"Common.Back"`="Back" (`ChatListUI/Sources/ChatListController.swift:380`).
- Proxy button: `"VoiceOver.Navigation.ProxySettings"` (`TelegramUI/Components/ChatListTitleView/Sources/ChatListTitleView.swift:227`).
- Lists announce scroll position with `"VoiceOver.ScrollStatus"` = "Row %1$@ of %2$@" (`ChatListUI/Sources/ChatListContainerItemNode.swift:296`).

## 2. Message bubbles

The whole spec is built in one place: `ChatMessageAccessibilityData.init(item:isSelected:)`, `TelegramUI/Components/Chat/ChatMessageItemView/Sources/ChatMessageItemView.swift:90-616`. Bubble, sticker, animated-sticker and round-video nodes each copy it onto one `AccessibilityAreaNode` named `messageAccessibilityArea`, which covers the message:
- `ChatMessageBubbleItemNode.swift:5774-5786` (data is built at :1626)
- `ChatMessageStickerItemNode.swift:364-376`
- `ChatMessageAnimatedStickerItemNode.swift:784-796`
- `ChatMessageInstantVideoItemNode.swift:248-260`

So **one message = one element**, with label, value, hint, traits and custom actions.

### Definitions
- `isIncoming` = `message.effectivelyIncoming(accountPeerId)` (:97).
- `announceIncomingAuthors` = the chat is a `TelegramGroup` or a megagroup channel (:98-105). Only then do the "…From: %@" labels and the plural "recipients" status variants appear.
- `authorName` = `message.author.displayTitle` (:112).

### Label by kind
The label is set by the first matching media in `message.media` (loop :118-440). It falls back to the author at :495-505.

| Kind | Incoming, group (`announceIncomingAuthors`) | Incoming, 1:1/channel | Outgoing | Value text part | Traits / hint |
|---|---|---|---|---|---|
| Photo `TelegramMediaImage` (:119-135) | `VoiceOver.Chat.PhotoFrom` "Photo, from: %@" | `VoiceOver.Chat.Photo` "Photo" | `VoiceOver.Chat.YourPhoto` "Your photo" | "" or `"\n" + VoiceOver.Chat.Caption` "Caption: %@" | `.image` |
| Sticker (`.Sticker`, non-tgs) (:156-165) | `VoiceOver.Chat.StickerFrom` "Sticker, from: %@" | `VoiceOver.Chat.Sticker` "Sticker" | `VoiceOver.Chat.YourSticker` "Your sticker" | sticker's emoji (`displayText`) | none |
| Animated sticker (`application/x-tgsticker`) (:146-155) | `VoiceOver.Chat.AnimatedStickerFrom` "Animated sticker, from: %@" | `VoiceOver.Chat.AnimatedSticker` | `VoiceOver.Chat.YourAnimatedSticker` | emoji | none |
| Voice (`.Audio isVoice`) (:176-187) | `VoiceOver.Chat.VoiceMessageFrom` "Voice message, from: %@" | `VoiceOver.Chat.VoiceMessage` | `VoiceOver.Chat.YourVoiceMessage` | `VoiceOver.Chat.Duration` "Duration: %@" (voice duration format) | `.startsMediaSession`, hint `VoiceOver.Chat.PlayHint` "Double tap to play" |
| Music (`.Audio !isVoice`) (:188-204) | `VoiceOver.Chat.MusicFrom` "Music file, from: %@" | `VoiceOver.Chat.Music` "Music message" | `VoiceOver.Chat.YourMusic` | `VoiceOver.Chat.MusicTitle` "%1$@, by %2$@" (missing parts become "Unknown") + `VoiceOver.Chat.Duration`, with **no separator** | `.startsMediaSession`, PlayHint |
| Round video (`.Video` + `instantRoundVideo`) (:212-221) | `VoiceOver.Chat.VideoMessageFrom` "Video message, from: %@" | `VoiceOver.Chat.VideoMessage` | `VoiceOver.Chat.YourVideoMessage` | `VoiceOver.Chat.Duration` | `.startsMediaSession`, PlayHint |
| Video (`.Video`) (:222-233) | `VoiceOver.Chat.VideoFrom` "Video, from: %@" | `VoiceOver.Chat.Video` | `VoiceOver.Chat.YourVideo` | `VoiceOver.Chat.Duration` | `.startsMediaSession`, PlayHint |
| GIF | reads as **Video**: MP4 GIFs carry a `.Video` attribute and there is no GIF branch (a legacy `.gif` with only `.Animated` falls to File) | | | Duration | same as Video |
| File (anything else) (:238-254) | `VoiceOver.Chat.FileFrom` "File, from: %@" | `VoiceOver.Chat.File` | `VoiceOver.Chat.YourFile` | `"<fileName>. " + VoiceOver.Chat.Size` "Size: %@" (`ByteCountFormatter`) | hint `VoiceOver.Chat.OpenHint` "Double tap to open" |
| Contact (:270-354) | `VoiceOver.Chat.ContactFrom` "Shared contact, from: %@" | `VoiceOver.Chat.Contact` | `VoiceOver.Chat.YourContact` | see below | none |
| Poll (:355-439) | `VoiceOver.Chat.AnonymousPollFrom` "Anonymous poll, from: %@" | `VoiceOver.Chat.AnonymousPoll` | `VoiceOver.Chat.YourAnonymousPoll` | see below | none |
| Text / everything else (location, game, invoice, dice, animated emoji, service/action messages, giveaways…) | author displayTitle | author displayTitle | `VoiceOver.Chat.YourMessage` "Your message" | `chatListItemStrings` text: the message text, `"Message.Location"`, `"🎮 <game title>"`, the invoice title, or the service-message string | none |
| No author (channel post with no author peer) | `VoiceOver.Chat.Message` "Message" | | | | |

- Every file kind (sticker, voice, music, video, round, file) appends `"\n" + VoiceOver.Chat.Caption("…")` when the message has text (:255-258).
- Play/Open hints are set only when `isSelected == nil` (not in selection mode); `OpenLinkHint` applies whenever no other hint is set.
- An animated emoji is a text message, so it reads as "<author>/Your message" plus the emoji.

**Link preview** (`TelegramMediaWebpage` loaded, :260-269): text = `message.text + "\n" + VoiceOver.Chat.PagePreview` ("Page preview") + `". "` + (`VoiceOver.Chat.Title` "Title: %@" + `". "`) + page description. The label stays the author or "Your message".

**Contact value**:
1. `"<First Last>."`, or the organization name when there is no name.
2. Phones: a single phone gives `VoiceOver.Chat.ContactPhoneNumber` "Phone number". Several give `VoiceOver.Chat.ContactPhoneNumberCount` "%@ phone number(s)" + `": "`. Then the digits, spoken one at a time with spaces between them, numbers joined by `", "`, then `". "`.
3. Emails: `VoiceOver.Chat.ContactEmail` "Email" + `": "` for one, or `VoiceOver.Chat.ContactEmailCount` "%@ email address(es)" + `": "` for several. Then the list + `". "`.
4. `VoiceOver.Chat.ContactOrganization` "Organization: %@" + `"."`.

**Poll value**:
1. `VoiceOver.Chat.Title(question)` + `". "`.
2. `VoiceOver.Chat.PollOptionCount` "%@ option(s):" + `": "`. The key text already ends in a colon, so the result is "3 options:: ".
3. The options joined by `", "`. Each option gets `", " + VoiceOver.Chat.OptionSelected` ("selected") if the user voted for it. Once the user has voted or the poll is closed, each option also gets `", NN%"`.
4. `". "`.
5. `VoiceOver.Chat.PollVotes` "%@ vote(s)", or `VoiceOver.Chat.PollNoVotes` "No votes".
6. `VoiceOver.Chat.PollFinalResults` "Final results" if the poll is closed, appended with no separator.

The label always says "Anonymous poll", even for public polls.

### Value: full composition (:442-490)
Parts are joined by `\n`, in this order:
1. Only when in selection mode and the message is selected: `VoiceOver.Chat.Selected` "Selected". In selection mode `.startsMediaSession` is always added.
2. The kind text from the table above.
3. Date: `DateFormatter.localizedString(dateStyle: .medium, timeStyle: .short)`, i.e. the full date and time, not just the time.
4. Only for outgoing messages (and not for the reply-quoted message), one of:
   - `VoiceOver.Chat.Sending` "Sending", or
   - `VoiceOver.Chat.Failed` "Failed to send", or
   - otherwise: `VoiceOver.Chat.SeenByRecipient(s)` "Seen by recipient(s)" if read, then **independently of read state** and with no separator, for consumable media (voice/round), `VoiceOver.Chat.NotPlayedByRecipient(s)` "Not played by recipient(s)" or `VoiceOver.Chat.PlayedByRecipient(s)` "Played by recipient(s)".
   - The plural variants are used in groups.
   - An unread outgoing non-consumable message has an empty line here.

### Prefixes and suffixes (:509-608)
- **Reply** (`ReplyMessageAttribute` with a loaded message):
  - The label becomes `"<replyLabel> . <label>"`. Note the separator is `" . "`, with a space before the dot.
  - `replyLabel`: `VoiceOver.Chat.ReplyFrom` "Reply to message from: %@" if the replied message is incoming and has an author, `VoiceOver.Chat.Reply` "Reply to message" if it is incoming with no author, else `VoiceOver.Chat.ReplyToYourMessage` "Reply to your message".
  - The value gets `". " + VoiceOver.Chat.ReplyingToMessage` "In reply to message: %@". The argument is the replied message's own value: its text + date, with no status.
- **Forward**:
  - The label becomes `"<forwardLabel>. <label>"`. The forward prefix goes before the reply prefix.
  - `VoiceOver.Chat.ForwardedFromYou` "Forwarded from you" when the original author is the account.
  - Otherwise `VoiceOver.Chat.ForwardedFrom` "Forwarded from: %@". The argument is `"<peer> (<signature>)"`, or just the peer, or just the signature.
- **Single link**: if the text has exactly one `.Url`/`.TextUrl` entity, hint = `VoiceOver.Chat.OpenLinkHint` "Double tap to open link" (only when no other hint was set), and activate opens that URL (`ChatMessageBubbleItemNode.swift:962-965`).
- **Not exposed**: edited flag, view count, reactions, channel signature, pinned, reply-thread count, sender rank/badges. The comments footer button does get its own label: `"Conversation.ViewReply"` "View Reply" / `"Conversation.MessageLeaveComment"` "Leave a Comment" / a count (`ChatMessageCommentFooterContentNode.swift:150-268`).

### Activation and custom actions
- **Activate** (double tap), `ChatMessageBubbleItemNode.swift:950-967`: each content node's `accessibilityActivate()` is tried first (play voice/video, open media). If none handles it, the single URL is opened.
- **Custom actions** (:585-604), only outside selection mode:
  - `VoiceOver.MessageContextReply` "Reply", when `canSetupReply == .reply` and the message is not expired media or a service action (call messages are allowed). Performed with `controllerInteraction.setupReply(id)`.
  - `VoiceOver.MessageContextOpenMessageMenu` "Open message menu", always. Performed with `openMessageContextMenu(...)` (`ChatMessageBubbleItemNode.swift:5789-5810`).
- **Inline keyboard buttons**: each button is its own `AccessibilityAreaNode` with label = button title and trait `.button` (`ChatMessageActionButtonsNode.swift:98-105, :598`).
- **Poll and todo options**: `buttonNode.accessibilityLabel = option.text` (`ChatMessagePollBubbleContentNode.swift:1048`, `ChatMessageTodoBubbleContentNode.swift:813`).

### Chat-level
- Unread separator: label `"Conversation.UnreadMessages"` "Unread Messages", trait `.staticText` (`ChatMessageItemImpl/Sources/ChatUnreadItem.swift:106, :170`).
- Scroll status: `VoiceOver.ScrollStatus` "Row %1$@ of %2$@" (`TelegramUI/Sources/ChatHistoryListNode.swift:1063-1069`).
- Selection announcement: `VoiceOver.Chat.MessagesSelected` "%@ message(s) selected", posted as `UIAccessibility.announcement` (`TelegramUI/Sources/Chat/ChatControllerLoadDisplayNode.swift:1834`, `TelegramUI/Sources/ChatController.swift:2319`).
- Selection bottom panel (`ChatMessageSelectionInputPanelNode.swift:215-241`): `VoiceOver.MessageContextDelete` "Delete", `VoiceOver.MessageContextReport` "Report", `VoiceOver.MessageContextForward` "Forward", `VoiceOver.MessageContextShare` "Share", `VoiceOver.MessageSelectionButtonTag` "Tag".
- Context menu: a dismiss element labeled `VoiceOver.DismissContextMenu` "Dismiss Context Menu" (`ContextControllerImpl/Sources/ContextControllerImpl.swift:142`).
- Date headers have no accessibility code.

## 3. Chat input panel

| Control | Label / hint / traits | Source |
|---|---|---|
| Attach | `VoiceOver.AttachMedia` "Send media", `.button`, plus `.notEnabled` when slow mode blocks media | `ChatTextInputPanelNode/Sources/ChatTextInputPanelNode.swift:730-731, :1738` |
| Bot menu button | `"Conversation.InputMenu"` "Menu", later the menu button's own text | `ChatTextInputPanelNode.swift:706, :1951` |
| Send / mic / stop (one element; `updateAccessibility`) | traits `.button` (`[.button, .notEnabled]` at init). Stop visible: `VoiceOver.Chat.Stop` "Stop". Mic in audio mode: `VoiceOver.Chat.RecordModeVoiceMessage` "Voice message", hint `VoiceOver.Chat.RecordModeVoiceMessageInfo` "Double tap and hold to record voice message. Slide up to pin recording, slide left to cancel. Double tap to switch to video." Mic in video mode: `VoiceOver.Chat.RecordModeVideoMessage` + hint `…VideoMessageInfo`. Otherwise `"MediaPicker.Send"` "Send". | `ChatTextInputActionButtonsNode/Sources/ChatTextInputActionButtonsNode.swift:231-232, :584-601` |
| While recording | extra element `VoiceOver.MessageContextSend` "Send", `[.button, .startsMediaSession]`, activate = finish and send. The mic buttons are hidden from VoiceOver. | `ChatTextInputPanelNode.swift:3474-3492` |
| Recording lock | `VoiceOver.Recording.StopAndPreview` "Stop and preview" | `ChatTextInputMediaRecordingButton/Sources/LockView.swift:39` |
| Recording cancel | `"Common.Cancel"`, `.button` | `ChatTextInputAudioRecordingCancelIndicator.swift:43-44` |
| Recorded preview waveform | `VoiceOver.Chat.RecordPreviewVoiceMessage` "Preview voice message", `.startsMediaSession` | `ChatRecordingPreviewInputPanelNode.swift:260, :404` |
| Accessory icons in the text field (`AccessoryItemIconButton.swift:145-176`, `.button`) | `VoiceOver.Keyboard` "Keyboard" (when emoji/stickers are shown) · `VoiceOver.Stickers` "Stickers" (emoji/sticker toggle) · `VoiceOver.BotKeyboard` "Bot Keyboard" · `VoiceOver.BotCommands` "Bot Commands" · `VoiceOver.SilentPostOn` "Silent Broadcast On" / `VoiceOver.SilentPostOff` "Silent Broadcast Off" · `VoiceOver.SuggestPost` "Suggest Post" · `VoiceOver.SelfDestructTimerOn` "Self-destruct Timer: %@" / `VoiceOver.SelfDestructTimerOff` "Self-destruct Timer Off" · `VoiceOver.ScheduledMessages` "Scheduled Messages" · `VoiceOver.GiftPremium` "Gift Telegram Premium" | same |
| Reply panel | close: `VoiceOver.DiscardPreparedContent` "Discard". Panel: `"<header>.\n<preview text>"`, where header is `"Chat.ReplyPanel.AccessibilityReplyToMessageFrom"` "Reply to message. From: %@" / `"…ReplyToYourMessage"` "Reply to your message." / `"…ReplyToMessage"` "Reply to message." | `ReplyAccessoryPanelNode.swift:60, :324-332` |
| Edit panel | close: `VoiceOver.DiscardPreparedContent`. Panel: `"<title>.\n<text>"`, where title is `"Conversation.EditingMessagePanelTitle"` "Edit Message" / `"…EditingPhotoPanelTitle"` "Edit Photo" / `"…EditingCaptionPanelTitle"` "Edit Caption" / `"…EditingQuickReplyPanelTitle"` | `TelegramUI/Sources/EditAccessoryPanelNode.swift:88, :286-320` |
| Forward panel | close: `VoiceOver.DiscardPreparedContent`. Panel: `"Forward message(s). From: <authors>.\n<text>"`; the "Forward message(s)" part is hardcoded English | `ForwardAccessoryPanelNode.swift:128, :366-372` |
| Bot keyboard buttons | label = button title, `.button` | `ChatButtonKeyboardInputNode/Sources/ChatButtonKeyboardInputNode.swift:47, :104` |
| Text field | no custom label; it is the standard `UITextView`. The panel only overrides the Speak/Spell-out menu actions (`_accessibilitySpeak…`, `ChatTextInputPanelNode.swift:4969-4990`) | |
| Mention / command / hashtag suggestions | lists with `VoiceOver.ScrollStatus` | `TelegramUI/Sources/*ChatInputContextPanelNode.swift` |
| Report panel | `VoiceOver.MessageContextReport` "Report" | `TelegramUI/Sources/ChatMessageReportInputPanelNode.swift:39` |

Silent and schedule have no separate send-menu labels; they are reached through the accessory icons and the context menu.

## 4. Chat header / navigation bar

- Navigation bar element order (`TelegramUI/Components/NavigationBarImpl/Sources/NavigationBarImpl.swift:242-268`): back, left button, title (or titleView), right buttons, content node.
- Back button: its label is its visible text (previous screen title or `"Common.Back"` "Back"), `.button` (`NavigationButtonNode.swift:366-408`). Generic buttons use `UIBarButtonItem.accessibilityLabel`, falling back to their visible text.
- **Chat title view** (`TelegramUI/Components/ChatTitleView/Sources/ChatTitleView.swift:734-747, :803`, mirrored in `ChatTitleComponent.swift:599-610, :836`). It is a single element with trait `.header`.
  - Label: the title segments concatenated (peer name, or the "Saved Messages"/topic title).
  - Value: the subtitle state string. That is either the typing activity ("typing…", "recording voice message", `Chat.MultipleTypingPair`, etc.) or the status: online/last seen, "N members", "bot", or a custom subtitle.
  - The verified/premium/muted icons in the title are not spoken.
- Avatar (info) button: `"Conversation.ContextMenuOpenProfile"` "Open Profile" for every peer type (`TelegramUI/Sources/ChatControllerContentData.swift:639-644, :1586-1591`, applied at `Chat/ChatControllerLoadDisplayNode.swift:236-243`). `VoiceOver.Chat.Profile` / `.GroupInfo` / `.ChannelInfo` exist in the strings but are **unused**.
- Right buttons (`TelegramUI/Sources/ChatInterfaceStateNavigationButtons.swift`):
  - search: `"Conversation.Search"` "Search" (:110 etc.)
  - cancel selection: `"Common.Cancel"` (:98)
  - close: `"Common.Close"` (:70)
  - edit: `"Common.Done"` (:183), note the visible title is "Edit"
  - clear all / clear cache: their titles (:50, :55)
- There is no call or "more" button in the iOS chat navigation bar; those live in peer info.
- Media player header (`TelegramUI/Components/MediaPlaybackHeaderPanelComponent/Sources/MediaNavigationAccessoryHeaderNode.swift:194-341`):
  - rate button: `VoiceOver.Media.PlaybackRate` + hint `VoiceOver.Media.PlaybackRateChange`
  - close: `VoiceOver.Media.PlaybackStop` "Stop playback"
  - play/pause: `VoiceOver.Media.PlaybackPlay` / `VoiceOver.Media.PlaybackPause`

## 5. Media gallery viewer

The gallery has very little coverage on iOS:
- **Escape (two-finger Z) closes the gallery**: `accessibilityPerformEscape` calls `controller.dismiss` (`GalleryUI/Sources/GalleryControllerNode.swift:658-664`).
- More button: `"Common.More"` "More" (`GalleryUI/Sources/Items/ChatImageGalleryItem.swift:537, :945`, `UniversalVideoGalleryItem.swift:1982`).
- Footer delete/fullscreen/share/edit labels (`"Gallery.VoiceOver.Delete"` "Delete", `"…Fullscreen"`, `"…Share"`, `"…Edit"`) are **commented out** (`ChatItemGalleryFooterContentNode.swift:645-659`). The PiP label `"Gallery.VoiceOver.PictureInPicture"` is also commented out (`UniversalVideoGalleryItem.swift:1911-1914`).
- There is no page/position announcement, no play/pause label and no caption element.

## 6. Calls UI

- The **live** 1:1 call screen is `CallControllerNodeV2` → `TelegramUI/Components/Calls/CallScreen/Sources/PrivateCallScreen.swift`, and it has **no accessibility code**. `LegacyCallControllerButtonsNode` has none either.
- `TelegramCallsUI/Sources/CallControllerButtonsNode.swift:437-564` is an older but complete reference that is not instantiated anywhere. Every button gets traits `.button`:

| Button | Label | Value | Extra traits |
|---|---|---|---|
| accept | `"Call.Accept"` "Accept" | | |
| end / decline | `"Call.Decline"` "Decline" / `"Call.End"` "end" (outgoing uses `Call.End`) | | |
| camera | `"Call.Camera"` "camera" | | `.selected` when on, `.notEnabled` |
| flip | `"Call.Flip"` "flip" | | `.notEnabled` |
| sound output | `"Call.Speaker"` "speaker" (builtin/speaker) or `"Call.Audio"` "audio" (others) | "Bluetooth" / "Airpods" / "Airpods Pro" / "Airpods Max" (hardcoded) / `"Call.AudioRouteHeadphones"` "Headphones" | `.selected` when on speaker |
| mute | `"Call.Mute"` "mute" | | `.selected` when muted |

- The same old file's status node (`CallControllerStatusNode.swift:125-128, :206-207`) has two elements: title (`.staticText`) and status text (`[.staticText, .updatesFrequently]`).
- Other call strings: `"Call.VoiceOver.Minimize"` "Minimize Call" (unused). The call list uses `"Call.VoiceOver.{Voice,Video}Call{Incoming,Outgoing,Missed,Canceled}"` (`CallListUI/Sources/CallListCallItem.swift:479-498`). Audio route sheet: `TelegramCallsUI/Sources/CallRouteActionSheetItem.swift`.

## 7. Stories viewer

There is no accessibility code anywhere under `TelegramUI/Components/Stories/` (no label, value, hint, traits or escape).

## 8. All VoiceOver keys (en)

Keys named `VoiceOver.*` (136 keys):

```
VoiceOver.Editing.ClearText = Clear text
VoiceOver.Recording.StopAndPreview = Stop and preview
VoiceOver.Media.PlaybackRate = Playback rate
VoiceOver.Media.PlaybackRateNormal = Normal
VoiceOver.Media.PlaybackRateFast = Fast
VoiceOver.Media.PlaybackRateChange = Double tap to change
VoiceOver.Media.PlaybackStop = Stop playback
VoiceOver.Media.PlaybackPlay = Play
VoiceOver.Media.PlaybackPause = Pause
VoiceOver.Navigation.Compose = Compose
VoiceOver.Navigation.Search = Search
VoiceOver.Navigation.ProxySettings = Proxy settings
VoiceOver.DiscardPreparedContent = Discard
VoiceOver.AttachMedia = Send media
VoiceOver.Chat.RecordPreviewVoiceMessage = Preview voice message
VoiceOver.Chat.RecordModeVoiceMessage = Voice message
VoiceOver.Chat.RecordModeVoiceMessageInfo = Double tap and hold to record voice message. Slide up to pin recording, slide left to cancel. Double tap to switch to video.
VoiceOver.Chat.RecordModeVideoMessage = Video message
VoiceOver.Chat.RecordModeVideoMessageInfo = Double tap and hold to record video message. Slide up to pin recording, slide left to cancel. Double tap to switch to audio.
VoiceOver.Chat.Message = Message
VoiceOver.Chat.YourMessage = Your message
VoiceOver.Chat.ReplyFrom = Reply to message from: %@
VoiceOver.Chat.Reply = Reply to message
VoiceOver.Chat.ReplyToYourMessage = Reply to your message
VoiceOver.Chat.ForwardedFrom = Forwarded from: %@
VoiceOver.Chat.ForwardedFromYou = Forwarded from you
VoiceOver.Chat.PhotoFrom = Photo, from: %@
VoiceOver.Chat.Photo = Photo
VoiceOver.Chat.YourPhoto = Your photo
VoiceOver.Chat.VoiceMessageFrom = Voice message, from: %@
VoiceOver.Chat.VoiceMessage = Voice message
VoiceOver.Chat.YourVoiceMessage = Your voice message
VoiceOver.Chat.MusicFrom = Music file, from: %@
VoiceOver.Chat.Music = Music message
VoiceOver.Chat.YourMusic = Your music message
VoiceOver.Chat.VideoFrom = Video, from: %@
VoiceOver.Chat.Video = Video
VoiceOver.Chat.YourVideo = Your video
VoiceOver.Chat.VideoMessageFrom = Video message, from: %@
VoiceOver.Chat.VideoMessage = Video message
VoiceOver.Chat.YourVideoMessage = Your video message
VoiceOver.Chat.FileFrom = File, from: %@
VoiceOver.Chat.File = File
VoiceOver.Chat.YourFile = Your file
VoiceOver.Chat.StickerFrom = Sticker, from: %@
VoiceOver.Chat.Sticker = Sticker
VoiceOver.Chat.YourSticker = Your sticker
VoiceOver.Chat.AnimatedStickerFrom = Animated sticker, from: %@
VoiceOver.Chat.AnimatedSticker = Animated sticker
VoiceOver.Chat.YourAnimatedSticker = Your animated sticker
VoiceOver.Chat.ContactFrom = Shared contact, from: %@
VoiceOver.Chat.Contact = Shared contact
VoiceOver.Chat.ContactPhoneNumberCount_1 = %@ phone number
VoiceOver.Chat.ContactPhoneNumberCount_any = %@ phone numbers
VoiceOver.Chat.ContactPhoneNumber = Phone number
VoiceOver.Chat.ContactEmailCount_1 = %@ email address
VoiceOver.Chat.ContactEmailCount_any = %@ email addresses
VoiceOver.Chat.ContactEmail = Email
VoiceOver.Chat.ContactOrganization = Organization: %@
VoiceOver.Chat.YourContact = Your shared contact
VoiceOver.Chat.AnonymousPollFrom = Anonymous poll, from: %@
VoiceOver.Chat.AnonymousPoll = Anonymous poll
VoiceOver.Chat.YourAnonymousPoll = Your Anonymous poll
VoiceOver.Chat.PollOptionCount_1 = %@ option:
VoiceOver.Chat.PollOptionCount_any = %@ options:
VoiceOver.Chat.PollVotes_1 = %@ vote
VoiceOver.Chat.PollVotes_any = %@ votes
VoiceOver.Chat.PollNoVotes = No votes
VoiceOver.Chat.PollFinalResults = Final results
VoiceOver.Chat.OptionSelected = selected
VoiceOver.Chat.PagePreview = Page preview
VoiceOver.Chat.Title = Title: %@
VoiceOver.Chat.Caption = Caption: %@
VoiceOver.Chat.Duration = Duration: %@
VoiceOver.Chat.Size = Size: %@
VoiceOver.Chat.MusicTitle = %1$@, by %2$@
VoiceOver.Chat.PlayHint = Double tap to play
VoiceOver.Chat.OpenHint = Double tap to open
VoiceOver.Chat.OpenLinkHint = Double tap to open link
VoiceOver.Chat.SeenByRecipient = Seen by recipient
VoiceOver.Chat.SeenByRecipients = Seen by recipients
VoiceOver.Chat.Selected = Selected
VoiceOver.MessageContextDelete = Delete
VoiceOver.MessageContextReport = Report
VoiceOver.MessageContextForward = Forward
VoiceOver.MessageContextShare = Share
VoiceOver.MessageContextSend = Send
VoiceOver.MessageContextReply = Reply
VoiceOver.MessageContextOpenMessageMenu = Open message menu
VoiceOver.Keyboard = Keyboard
VoiceOver.Stickers = Stickers
VoiceOver.ScheduledMessages = Scheduled Messages
VoiceOver.BotCommands = Bot Commands
VoiceOver.BotKeyboard = Bot Keyboard
VoiceOver.SilentPostOn = Silent Broadcast On
VoiceOver.SilentPostOff = Silent Broadcast Off
VoiceOver.SelfDestructTimerOn = Self-destruct Timer: %@
VoiceOver.SelfDestructTimerOff = Self-destruct Timer Off
VoiceOver.Common.SwitchHint = Double Tap To Toggle
VoiceOver.Common.On = On
VoiceOver.Common.Off = Off
VoiceOver.Chat.MessagesSelected_0 = %@ messages selected
VoiceOver.Chat.MessagesSelected_1 = %@ message selected
VoiceOver.Chat.MessagesSelected_2 = %@ messages selected
VoiceOver.Chat.MessagesSelected_3_10 = %@ messages selected
VoiceOver.Chat.MessagesSelected_many = %@ messages selected
VoiceOver.Chat.MessagesSelected_any = %@ messages selected
VoiceOver.DismissContextMenu = Dismiss Context Menu
VoiceOver.Chat.GoToOriginalMessage = Go to message
VoiceOver.Chat.UnreadMessages_0 = %@ unread messages
VoiceOver.Chat.UnreadMessages_1 = %@ unread message
VoiceOver.Chat.UnreadMessages_2 = %@ unread messages
VoiceOver.Chat.UnreadMessages_3_10 = %@ unread messages
VoiceOver.Chat.UnreadMessages_many = %@ unread messages
VoiceOver.Chat.UnreadMessages_any = %@ unread messages
VoiceOver.ChatList.Message = Message
VoiceOver.ChatList.OutgoingMessage = Outgoing Message
VoiceOver.ChatList.MessageFrom = From: %@
VoiceOver.ChatList.MessageRead = Read
VoiceOver.ChatList.MessageEmpty = Empty
VoiceOver.Chat.Profile = Profile
VoiceOver.Chat.GroupInfo = Group Info
VoiceOver.Chat.ChannelInfo = Channel Info
VoiceOver.AuthSessions.CurrentSession = Current Session
VoiceOver.ScrollStatus = Row %1$@ of %2$@
VoiceOver.Chat.Sending = Sending
VoiceOver.Chat.Failed = Failed to send
VoiceOver.Chat.PlayedByRecipient = Played by recipient
VoiceOver.Chat.PlayedByRecipients = Played by recipients
VoiceOver.Chat.NotPlayedByRecipient = Not played by recipient
VoiceOver.Chat.NotPlayedByRecipients = Not played by recipients
VoiceOver.Chat.ReplyingToMessage = In reply to message: %@
VoiceOver.GiftPremium = Gift Telegram Premium
VoiceOver.MessageSelectionButtonTag = Tag
VoiceOver.SuggestPost = Suggest Post
VoiceOver.Chat.Stop = Stop
```

Namespaced `*.VoiceOver.*` keys:

```
ProxyServer.VoiceOver.Active = Active
Call.VoiceOver.VoiceCallOutgoing = Outgoing Voice Call
Call.VoiceOver.VideoCallOutgoing = Outgoing Video Call
Call.VoiceOver.VoiceCallIncoming = Incoming Voice Call
Call.VoiceOver.VideoCallIncoming = Incoming Video Call
Call.VoiceOver.VoiceCallMissed = Missed Voice Call
Call.VoiceOver.VideoCallMissed = Missed Video Call
Call.VoiceOver.VoiceCallCanceled = Cancelled Voice Call
Call.VoiceOver.VideoCallCanceled = Cancelled Video Call
InstantPage.VoiceOver.IncreaseFontSize = Increase Font Size
InstantPage.VoiceOver.DecreaseFontSize = Decrease Font Size
InstantPage.VoiceOver.ResetFontSize = Reset Font Size
Contacts.VoiceOver.AddContact = Add Contact
Call.VoiceOver.Minimize = Minimize Call
Login.VoiceOver.PhoneCountryCode = Phone country code
Login.VoiceOver.PhoneNumber = Phone number
Login.VoiceOver.Password = Password
Gallery.VoiceOver.Delete = Delete
Gallery.VoiceOver.Fullscreen = Fullscreen
Gallery.VoiceOver.Share = Share
Gallery.VoiceOver.Edit = Edit
Gallery.VoiceOver.Stickers = Stickers
Gallery.VoiceOver.PictureInPicture = Picture-in-Picture
Appearance.VoiceOver.Theme = %@ Theme
MediaPicker.VoiceOver.Camera = Camera
```

## Not covered by iOS

- Chat list row: time, muted/pinned/verified/online state, typing and draft. Only the name, unread count and last-message preview are spoken.
- Message bubbles: edited flag, view count, reactions, signatures, pinned state. Message date headers. Location, game, invoice and GIF have no own labels (GIF reads as "Video").
- `VoiceOver.Chat.Profile`, `VoiceOver.Chat.GroupInfo`, `VoiceOver.Chat.ChannelInfo`, `VoiceOver.Chat.GoToOriginalMessage`, `VoiceOver.Navigation.Compose`, `VoiceOver.Navigation.Search` and `Call.VoiceOver.Minimize` are defined but never referenced.
- Media gallery: delete/share/forward/fullscreen/edit/PiP labels are commented out, and there is no position or play/pause. Only escape-to-close and "More" work.
- Calls: the live `PrivateCallScreen` has nothing. The labeled `CallControllerButtonsNode` is dead code.
- Stories viewer: nothing.
- Chat header: there are no call or "more" buttons in the chat navigation bar; title badges are not spoken.
