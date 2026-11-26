import argparse
import os
import pathlib
import subprocess
import tempfile


parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
parser.add_argument('--source-root', type=pathlib.Path)
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[3]
path = 'packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatHistoryViewForLocation.swift'
def read_source(path):
    if args.source_root:
        return (args.source_root / path).read_text()
    return subprocess.check_output(['git', '-C', str(root), 'show', f'HEAD:{path}'], text=True) if args.baseline else (root / path).read_text()


source = read_source(path)
start = source.index('    case let .InitialSearch(searchLocation, count, cachedAnchor):')
end = source.index('    case let .Navigation(', start)
branch = source[start:end]
state = branch[branch.index('        var preloaded'):branch.index('        let signal:')]
mapping = branch[branch.index('        return signal |> map'):]
implementation = '''func initialSearchUpdates(signal: Signal<(MessageHistoryView, ViewUpdateType, Int?), NoError>, cachedAnchor: Bool, searchLocation: ChatHistoryInitialSearchLocation, count: Int = 10) -> Signal<ChatHistoryViewUpdate, NoError> {
    let _chatLocation = 0
''' + state + mapping + '}\n'
scroll_start = source.index('    case let .Scroll(index, anchorIndex, sourceIndex, scrollPosition, count, animated):', end)
scroll_end = source.index('\nprivate func extractAdditionalData', scroll_start)
scroll_branch = source[scroll_start:scroll_end]
scroll_mapping = scroll_branch[scroll_branch.index('        return signal |> map'):scroll_branch.rfind('\n    }')]
implementation += '''func scrollUpdates(signal: Signal<(MessageHistoryView, ViewUpdateType, Int?), NoError>) -> Signal<ChatHistoryViewUpdate, NoError> {
    let _chatLocation = 0
    var first = true
    let chatScrollPosition = ChatHistoryViewScrollPosition.index(index: .message(MessageIndex(value: 50)), position: .center(id: 50, innerId: nil, animated: true, focus: Focus(focus: true), inset: 0), directionHint: .Down, animated: true)
''' + scroll_mapping + '}\n'
package = pathlib.Path(tempfile.mkdtemp(prefix='telegram-news-chat-focus-'))
tests = package / 'Tests'
tests.mkdir()
dependency = root / 'submodules/telegram-ios/submodules/SSignalKit'
(package / 'Package.swift').write_text(f'''// swift-tools-version:5.5
import PackageDescription
let package = Package(
    name: "NewsChatFocusRegression",
    platforms: [.macOS(.v10_13)],
    dependencies: [.package(name: "SSignalKit", path: "{dependency}")],
    targets: [.testTarget(name: "NewsChatFocusRegressionTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")]
)
''')
fixture = pathlib.Path(__file__).with_name('NewsChatFocusRegressionTests.swift').read_text()
(tests / 'NewsChatFocusRegressionTests.swift').write_text('import Foundation\nimport XCTest\nimport SwiftSignalKit\n\n' + implementation + fixture)
table_source = read_source('packages/TGUIKit/Sources/TableView.swift')
short_start = table_source.index('        if documentHeight < height {')
short_end = table_source.index('        if let item = item {', short_start)
short_branch = table_source[short_start:short_end]
stationary_start = table_source.rindex('\n        } else {', short_start, table_source.index('    open override func accessibilityParent()', short_end))
stationary_branch = table_source[stationary_start:table_source.index('    open override func accessibilityParent()', short_end)]
stationary_start = stationary_branch.index('            if let ')
stationary_end = stationary_branch.index('            } else {', stationary_start)
stationary_branch = stationary_branch[stationary_start:stationary_end] + '            }'

save_start = table_source.index('        func saveVisible(_ side: TableSavingSide)')
save_end = table_source.index('        switch state {', save_start)
save_function = table_source[save_start:save_end]
case_start = table_source.index('        case let .saveVisible(side,', save_end)
case_end = table_source.index('        case .animate:', case_start)
save_case = table_source[case_start:case_end]
after_start = table_source.index('        self.endUpdates()', case_end)
after_end = table_source.index('        self.updatedItems?', after_start)
after_updates = table_source[after_start:after_end].replace('        self.endUpdates()', '')
controller_source = read_source('packages/ChatUI/Sources/ChatUI/ChatController.swift')
stream_start = controller_source.find('        let historyViewUpdateId =')
if stream_start == -1:
    stream_start = controller_source.index('        let historyViewUpdate = historyViewUpdate1')
stream_end = controller_source.index('        let animatedEmojiStickers:', stream_start)
stream = controller_source[stream_start:stream_end]
state = 'let previousHistoryViewUpdateId = Atomic<Int?>(value: nil)' if 'let previousHistoryViewUpdateId =' in controller_source else ''
classification_start = controller_source.find('            let isNewHistoryViewUpdate =')
if classification_start == -1:
    classification_start = controller_source.index('            let isLoading: Bool', controller_source.index('        let historyViewTransition ='))
classification_end = controller_source.index('            if let updatedValue = previousUpdatingMedia', classification_start)
classification = controller_source[classification_start:classification_end]
initial_start = controller_source.index('        let prevIsLoading =')
initial_end = controller_source.index('            var initialIndex:', initial_start)
initial_condition = controller_source[initial_start:initial_end] + 'return true\n        }\n        return false'
combined_fixture = pathlib.Path(__file__).with_name('CombinedHistoryUpdateTests.swift').read_text()
combined_fixture = combined_fixture.replace('__HISTORY_STREAM__', stream).replace('__UPDATE_STATE__', state).replace('__CLASSIFICATION__', classification).replace('__INITIAL_CONDITION__', initial_condition)
(tests / 'CombinedHistoryUpdateTests.swift').write_text(combined_fixture)
if '            case let .keepInPlace(messageId):' in controller_source:
    keep_start = controller_source.index('            case let .keepInPlace(messageId):')
    keep_end = controller_source.index('            case .unread', keep_start)
    keep_branch = controller_source[keep_start:keep_end]
else:
    keep_branch = 'case .keepInPlace: scrollToItem = .saveVisible(.lower, false)'
table_fixture = pathlib.Path(__file__).with_name('TableFocusRegressionTests.swift').read_text()
table_fixture = table_fixture.replace('__SHORT_DOCUMENT_BRANCH__', short_branch).replace('__SAVE_VISIBLE_FUNCTION__', save_function).replace('__SAVE_VISIBLE_CASE__', save_case).replace('__AFTER_UPDATES__', after_updates).replace('__KEEP_IN_PLACE_CASE__', keep_branch).replace('__STATIONARY_BRANCH__', stationary_branch)
(tests / 'TableFocusRegressionTests.swift').write_text(table_fixture)
source_label = str(args.source_root) if args.source_root else ("baseline" if args.baseline else "working tree")
print(f"Testing {source_label}: history mapping, combined updates, anchor resolution, and native table branches in {package}", flush=True)
environment = os.environ.copy()
environment['CLANG_MODULE_CACHE_PATH'] = str(package / 'module-cache')
environment['SWIFTPM_MODULECACHE_OVERRIDE'] = str(package / 'module-cache')
raise SystemExit(subprocess.run(['swift', 'test', '--disable-sandbox', '--package-path', str(package), '--cache-path', str(package / 'cache')], env=environment).returncode)
