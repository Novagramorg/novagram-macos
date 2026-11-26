import argparse
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
source = (Path('/tmp/VideoEditorScrubbler-before-geometry.swift') if args.baseline else root / 'packages/AvatarEditorUI/Sources/AvatarEditorUI/VideoEditorScrubbler.swift').read_text()
def block(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]
def handler(control, event):
    end = source.index('}, for: .' + event + ')', source.index(control + '.set(handler:'))
    while source[source.rfind('.set(handler:', 0, end) - len(control):source.rfind('.set(handler:', 0, end)] != control:
        end = source.index('}, for: .' + event + ')', end + 1)
    start = source.rfind(control + '.set(handler:', 0, end)
    return block(source[start:], control + '.set(handler:').split('handler: ', 1)[1]
draw = block(source[source.index('open class VideoEditorScrubblerControl'):], '    public override func draw(').replace('public override ', '')
methods = draw + '\n' + block(source[source.index('open class VideoEditorScrubblerControl'):], '    public override func layout()').replace('public ', '')
if not args.baseline:
    methods += '\n' + block(source, '    func timelinePosition') + '\n' + block(source, '    private func framePosition').replace('private ', '')
controller = (Path('/tmp/VideoAvatarModalController-before-geometry.swift') if args.baseline else root / 'packages/AvatarEditorUI/Sources/AvatarEditorUI/VideoAvatarModalController.swift').read_text()
positions = [line.strip() for line in controller.splitlines() if 'let point = NSMakePoint(self.controls.frame.minX + self.scrubberView.frame.minX' in line]
dots = [line.strip() for line in controller.splitlines() if 'keyFrameDotView.frame = NSMakeRect(self.controls.frame.minX + self.scrubberView.frame.minX' in line]
assert len(positions) == len(dots) == 2
fixture = Path(__file__).with_name('AvatarScrubberGeometryTests.swift').read_text().replace('__VALUES__', block(source, 'public struct VideoScrubberValues').replace('public ', '')).replace('__METHODS__', methods)
for index in range(2):
    fixture = fixture.replace('__POSITION' + str(index) + '__', positions[index] + '\n' + dots[index])
for key, control, event in [('LONG', 'distance', 'LongMouseDown'), ('UP', 'distance', 'Up'), ('DRAG', 'distance', 'MouseDragging'), ('LEFT', 'leftTrim', 'MouseDragging'), ('RIGHT', 'rightTrim', 'MouseDragging')]:
    fixture = fixture.replace('__' + key + '__', handler(control, event))
with tempfile.TemporaryDirectory(prefix='avatar-scrubber-geometry-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "AvatarScrubberGeometry", targets: [.testTarget(name: "GeometryTests", path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/AvatarScrubberGeometryTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
