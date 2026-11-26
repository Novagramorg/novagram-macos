# Channel comments controls on layers

`ChannelCommentsBubbleControl` (the "123 comments" bar under channel posts) used one `TextView` per title segment (every digit of the count is its own segment, for the rolling-digit animation), an `ImageView` arrow and a `View` unread dot: 5–8 NSViews per channel post. `ChannelCommentsSmallControl` (sticker/round-video overlay) used an `ImageView` icon. All of these are now layers inside the existing `Button`; the button keeps clicks, hover background, `isEnabled`, the loading `ProgressIndicator` and its accessibility element (now labelled with the full title, e.g. "123 comments", instead of exposing one static text per digit).

## Lab

`generate.py` copies the production file twice into `Sources/CommentsHarness`: `Current.swift` unchanged, and `Legacy.swift` from `Reference/ChannelCommentsControls.swift.txt` (captured at `feca262f5`, hash in `Reference/provenance.json`) with its public types prefixed `Legacy`. Only the Postbox/SwiftSignalKit/AvatarUI/TelegramContext/TelegramTheme imports are removed; `Stubs.swift` supplies those symbols (asymmetric bitmap icons, solid avatar layers, theme colors). TGUIKit is the real package.

```sh
python3 tools/perflab/ChannelCommentsLab/generate.py "$PWD" tools/perflab/ChannelCommentsLab
swift test -c release --package-path tools/perflab/ChannelCommentsLab --scratch-path /tmp/ChannelCommentsLab-release
swift test --sanitize address --package-path tools/perflab/ChannelCommentsLab --scratch-path /tmp/ChannelCommentsLab-asan
COMMENTS_BENCHMARK=1 swift test -c release --package-path tools/perflab/ChannelCommentsLab --scratch-path /tmp/ChannelCommentsLab-release --skip-build --filter CommentsBenchmarkTests
```

Tests (7, release and ASAN pass): exact pixels for 49 bubble configurations (4 titles × 0/1/3 avatars × unread × bubble/list, plus loading) at 1×/2×/3× and 12 small-control configurations (wallpaper, titles, loading) at 1×/2×/3×; a negative control proving each text, arrow and dot layer is part of the compared pixels; identical CA animations (keys, from/to, duration, additive) for four animated count/avatar/unread/loading transitions, digit by digit including the outgoing ones; removed digits and dot leave the hierarchy after their animations; clicks over the text reach the button, no subviews at rest, VoiceOver label/role/press; text layers follow backing-scale changes.

Harness note: the snapshot helper must not call `setNeedsDisplay` on a plain layer whose `contents` is an assigned `CGImage` — `display()` would replace the image with an empty backing store. Production never redisplays these layers (the same pattern as `ChatRightIconLayer`).

## Results (release, 9 alternating batches, two runs)

| Operation | Legacy | Layers |
| --- | ---: | ---: |
| Construct + bind ("123 comments", 2 avatars, unread) | 62.1–67.1 µs | 25.3–27.5 µs (−59 %) |
| Count change update | 11.4–11.5 µs | 4.4–4.6 µs (−60 %) |
| Unchanged update | 1.86–1.93 µs | 1.92–1.97 µs (+2–4 %, noise level) |
| NSViews | 7 | 1 |

Each removed NSView also saves about 0.25 µs on every scroll frame (AppKit re-walks every view for tracking areas after each scroll step). Component timings, unattached rows; no app FPS claim.
