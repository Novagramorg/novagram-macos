import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/StoriesUI/Sources/StoriesUI/StoryPrivacyModalController.swift')
args = parser.parse_args()
source = args.source.read_text()
start = source.index('    controller.validateData = { _ in')
validate = source[start:source.index('    controller.didAppear =', start)]
fields = ''
disappear = ''
if '    let submissionDisposable =' in source:
    start = source.index('    let submissionDisposable =')
    fields = source[start:source.index('    var blockListOperationId:', start)]
    fields += '\n    actionsDisposable.add(submissionDisposable)\n'
    start = source.index('    controller.willDisappear =')
    disappear = source[start:source.index('    controller.validateData =', start)]
fixture = Path(__file__).with_name('StorySubmissionTests.swift').read_text()
if 'var audienceOperationId:' not in fields:
    fields += '\n    var audienceOperationId: UUID?\n'
fixture = fixture.replace('__FIELDS__', fields).replace('__VALIDATE__', validate).replace('__DISAPPEAR__', disappear)
with tempfile.TemporaryDirectory(prefix='story-submission-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StorySubmission", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "StorySubmissionTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/StorySubmissionTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
