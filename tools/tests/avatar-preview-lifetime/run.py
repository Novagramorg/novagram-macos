import argparse
import json
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
source = (Path('/tmp/VideoAvatarModalController-before-preview-lifetime.swift') if args.baseline else root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/VideoAvatarModalController.swift').read_text()
def block(source, marker):
    a = source.index(marker)
    b = (source.index(' -> Void {', a) + len(' -> Void {')) if marker == '    func setKeyFrame(' else source.index('{', a) + 1
    depth = 1
    while depth:
        depth += (source[b] == '{') - (source[b] == '}')
        b += 1
    return source[a:b]
controller = source[source.index('public final class VideoAvatarModalController'):] if 'public final class VideoAvatarModalController' in source else source[source.index('public class VideoAvatarModalController'):]
markers = ['    private func play()', '    @discardableResult private func seekToNormal', '    private func runKeyFrameUpdater', '    private func applyValuesToPlayer', '    private func updateUserInterface', '    public override func viewWillDisappear', '    public override func viewWillAppear']
if not args.baseline:
    markers.append('    private func invalidateKeyFramePreview')
methods = '\n'.join(block(controller, marker).replace('private ', '').replace('public ', '') for marker in markers)
valuesSource = (root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/VideoEditorScrubbler.swift').read_text()
rangeSource = (root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/EditedAvatarVideoExport.swift').read_text()
fixture = Path(__file__).with_name('AvatarPreviewLifetimeTests.swift').read_text().replace('__VALUES__', block(valuesSource, 'public struct VideoScrubberValues').replace('public ', '')).replace('__RANGE__', block(rangeSource, 'struct EditedAvatarVideoRange')).replace('__METHODS__', methods).replace('__VIEW__', block(source, '    func setKeyFrame(')).replace('__UPDATE__', block(source, '    func update(with image:'))
fixture = fixture.replace('__INPUT__', block(controller, '        genericView.scrubberView.updateValues =').split(' = ', 1)[1])
if args.baseline:
    fixture = fixture.replace('__INVALIDATE__', 'func invalidateKeyFramePreview() { appliedKeyFrame = nil; genericView.setKeyFrame(value: nil, animated: false) }')
else:
    fixture = fixture.replace('__INVALIDATE__', '')
with tempfile.TemporaryDirectory(prefix='avatar-preview-lifetime-') as directory:
    directory = Path(directory)
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "AvatarPreviewLifetime", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '''+json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))+''')], targets: [.testTarget(name: "PreviewTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory/'Tests').mkdir()
    (directory/'Tests/AvatarPreviewLifetimeTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
