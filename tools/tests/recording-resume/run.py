import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
def source(name, module):
    path = Path('/tmp')/(name+'-before-recording-resume.swift') if args.baseline else root/'packages'/module/'Sources'/module/(name+'.swift')
    return path.read_text()
def block(source, marker):
    a = source.index(marker); b = source.index('{', a) + 1; depth = 1
    while depth:
        depth += (source[b] == '{') - (source[b] == '}'); b += 1
    return source[a:b]
core = source('ChatRecordingState', 'MediaRecorderUI')
ui = source('ChatInputRecordingView', 'ChatUI')
pipeline = source('VideoRecorderPipeline', 'MediaRecorderUI')
core_methods = '\n'.join(block(core, marker).replace('public ', '').replace('final ', '') for marker in ['public func updateTrimRange', 'public var isTrimmed', 'public var pendingTrimRange', 'public final func applyTrimAndResume'])
ui_methods = '\n'.join(block(ui, marker).replace('private ', '').replace('public ', '') for marker in ['private func applyPreview', 'private func updateTrim', 'private func resetPreviewState', 'private func tearDownPlayback', 'private func resumeRecording', 'private func resumeAfterConfirm', 'private func discardRecording', 'private func stopAndSend', 'public override func viewWillMove', 'public override func viewDidMoveToWindow'])
if args.baseline:
    a = ui.index('            previewDisposable.set('); b = ui.index('            }))', a) + len('            }))')
    ui_methods += '\nfunc loadPreview() {\n'+ui[a:b]+'\n}'
else:
    ui_methods += '\n' + '\n'.join(block(ui, marker).replace('private ', '') for marker in ['private func loadPreview', 'private func setResuming'])
fixture = Path(__file__).with_name('RecordingResumeTests.swift').read_text()
fixture = fixture.replace('__CORE__', core_methods).replace('__UI__', ui_methods)
pipeline_method = block(pipeline, 'public func applyTrim').replace('public ', '')
if args.baseline: pipeline_method = pipeline_method.replace('self.composedRecording { path, _ in', 'self.composedRecording { result in\n guard let (path, _) = result else { return }')
fixture = fixture.replace('__PIPELINE__', pipeline_method)
fixture = fixture.replace('__RESULT__', 'applyTrimAndResume() |> map { value -> Bool in switch value {} }' if args.baseline else 'applyTrimAndResume()')
fixture = (root/'packages/ChatUI/Sources/ChatUI/RecordingTrimState.swift').read_text() + '\n' + fixture
with tempfile.TemporaryDirectory(prefix='recording-resume-') as directory:
    directory = Path(directory)
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "RecordingResume", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '''+json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))+''')], targets: [.testTarget(name: "ResumeTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory/'Tests').mkdir(); (directory/'Tests/RecordingResumeTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']
    if args.baseline: command += ['--skip', 'PipelineTests.testCompositionFailureRejectsTrimWithoutExport']
    raise SystemExit(subprocess.run(command).returncode)
