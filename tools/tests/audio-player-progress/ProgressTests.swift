import Cocoa

enum State { case waiting, stoped, playing(Double, Double, Double), paused(Double, Double, Double), fetching(Float) }
struct Song { let state: State }
final class Progress {
    var value: CGFloat = 0
    var style = 0
    func set(progress: CGFloat, animated: Bool, duration: Double = 0) { value = progress }
}
struct Colors { let grayText = 0 }
struct Theme { let colors = Colors() }
let theme = Theme()
enum Size { case short }
struct Font { static func normal(_ size: Size) -> Font { Font() } }
struct Text {
    let string: String
    static func initialize(string: String, color: Int, font: Font) -> Text { Text(string: string) }
}
struct TextViewLayout {
    let text: Text
    init(_ text: Text) { self.text = text }
    func measure(width: CGFloat) {}
}
final class Label {
    var string = ""
    func update(_ layout: TextViewLayout) { string = layout.text.string }
}
func timerText(_ value: Int) -> String { String(value) }
struct Handlings { func update(_ track: Song, controller: Int, animated: Bool) {} }
final class ListControls {
    let progress = Progress()
    let playedView = Label(), restView = Label()
    let handlings = Handlings()
    func update(_ track: Song) {
        let animated = false, controller = 0
        __LIST__
    }
}
final class InlineControls {
    let progressView = Progress()
    let playProgressStyle = 1, fetchProgressStyle = 2
    func update(_ song: Song) {
        let animated = false
        __INLINE__
    }
}
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { print(message); exit(1) }
}
let list = ListControls(), inline = InlineControls()
func update(_ state: State) { list.update(Song(state: state)); inline.update(Song(state: state)) }
func progress(_ value: CGFloat) {
    check(list.progress.value == value, "list progress is invalid or outside the expected range")
    check(inline.progressView.value == value, "inline progress is invalid or outside the expected range")
}
func times(_ played: String, _ remaining: String) {
    check(list.playedView.string.trimmingCharacters(in: .whitespaces) == played, "wrong elapsed time")
    check(list.restView.string.trimmingCharacters(in: .whitespaces) == remaining, "wrong remaining time")
}
switch CommandLine.arguments[1] {
case "normal":
    update(.playing(10.75, 60.9, 0.25)); progress(0.25); times("10", "50")
    update(.paused(30, 60, 0.5)); progress(0.5); times("30", "30")
case "nan-progress":
    update(.playing(10, 60, .nan)); progress(0)
case "infinite-progress":
    for value in [Double.infinity, -.infinity] { update(.playing(10, 60, value)); progress(0) }
case "progress-bounds":
    update(.playing(10, 60, -2)); progress(0)
    update(.paused(10, 60, 2)); progress(1)
    update(.fetching(-1)); progress(0)
    update(.fetching(2)); progress(1)
case "nan-current":
    for value in [Double.nan, .infinity, -.infinity] { update(.playing(value, 60, 0.2)); times("", "") }
case "invalid-duration":
    for duration in [Double.nan, .infinity, -.infinity, -1] { update(.playing(10, duration, 0.2)); times("10", "") }
case "huge-time":
    for value in [Double.greatestFiniteMagnitude, Double(Int.max)] { update(.playing(value, value, 1)); times("", "0") }
case "negative-time":
    update(.playing(-10, 60, 0)); times("0", "60")
case "past-end":
    update(.playing(200, 100, 2)); times("100", "0"); progress(1)
case "waiting":
    update(.playing(20, 100, 0.2)); update(.waiting); progress(0); times("", "")
case "fetching":
    for value in [Float.nan, .infinity, -.infinity] {
        update(.playing(20, 100, 0.2)); update(.fetching(value)); progress(0); times("", "")
    }
case "stopped":
    update(.playing(20, 100, 0.2)); update(.fetching(0.8)); update(.stoped)
    progress(0); times("", "")
    check(inline.progressView.style == inline.playProgressStyle, "stopped player kept fetching style")
default:
    fatalError("unknown test")
}
