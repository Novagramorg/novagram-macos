import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
parser.add_argument('--filter')
parser.add_argument('--include-unsafe-baseline', action='store_true')
args = parser.parse_args()
controller = Path('/tmp/CalendarController-before-selection.swift').read_text() if args.baseline else (root / 'packages/CalendarUI/Sources/CalendarUI/CalendarController.swift').read_text()
chat = Path('/tmp/ChatServiceItem-before-birthday-selection.swift').read_text() if args.baseline else (root / 'packages/ChatUI/Sources/ChatUI/ChatServiceItem.swift').read_text()
month = (root / 'packages/CalendarUI/Sources/CalendarUI/CalendarMonthController.swift').read_text()
def block(s, marker):
    a = s.index(marker); b = s.index('{', a) + 1; depth = 1
    while depth:
        depth += (s[b] == '{') - (s[b] == '}'); b += 1
    return s[a:b]
def clean(s):
    return '\n'.join(line for line in s.splitlines() if not line.startswith('import ')).replace('public ', '').replace('open ', '').replace('private ', '')
fixture = Path(__file__).with_name('CalendarSelectionTests.swift').read_text()
helper = (root / 'packages/ChatUI/Sources/ChatUI/ChatBirthdaySaveAction.swift').read_text()
fixture = fixture.replace('__SAVE_HELPER__', clean(helper))
fixture = fixture.replace('__CONTROLLER__', clean(controller).replace('Date()', 'clockNow'))
fixture = fixture.replace('__INTERACTIONS__', clean(block(month, 'public struct CalendarMonthInteractions')))
fixture = fixture.replace('__MONTH__', clean(block(month, 'public final class CalendarMonthStruct')))
a = month.index('open class CalendarMonthController:');b = month.index('    open override func getCenterBarViewOnce()', a)
month_controller = month[a:b] + block(month, '    open var isNextEnabled:') + '\n' + block(month, '    open var isPrevEnabled:') + '\n}'
fixture = fixture.replace('__MONTH_CONTROLLER__', clean(month_controller))
click = block(month, 'day.set(handler:').split('handler: ', 1)[1]
fixture = fixture.replace('__DAY_CLICK__', click)
chat = chat[chat.index('    public func openSuggestBirthday('):]
fixture = fixture.replace('__ACCEPT__', block(chat, 'accept: {').split('accept: ', 1)[1])
fixture = fixture.replace('__HIDE_YEAR__', block(chat, 'bottomLayout?.interactions.processURL =').split(' = ', 1)[1])
fixture = fixture.replace('__WRAP_LIFECYCLE__', '\n'.join(block(chat, '                override func ' + name) for name in ['viewWillAppear(', 'viewWillDisappear('] if '                override func ' + name in chat))
if args.baseline and not args.include_unsafe_baseline:
    marker = '    func testDateGetterDoesNotDependOnNavigationControllerType()'
    fixture = fixture.replace(block(fixture, marker), '    func testDateGetterDoesNotDependOnNavigationControllerType() throws { throw XCTSkip("Original force-cast traps; isolate this case") }')
with tempfile.TemporaryDirectory(prefix='calendar-selection-') as directory:
    directory = Path(directory)
    (directory / 'CalendarUtils').mkdir()
    for name in ['CalendarUtils.h', 'CalendarUtils.m']:
        (directory / 'CalendarUtils' / name).write_text((root / 'packages/CalendarUtils/Sources/CalendarUtils' / name).read_text())
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "CalendarSelection", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit')) + ''')], targets: [.target(name: "CalendarUtils", path: "CalendarUtils", publicHeadersPath: "."), .testTarget(name: "CalendarSelectionTests", dependencies: ["CalendarUtils", .product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/CalendarSelectionTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']
    if args.filter:
        command += ['--filter', args.filter]
    raise SystemExit(subprocess.run(command).returncode)
