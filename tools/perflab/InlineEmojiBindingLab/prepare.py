from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

lab = Path(__file__).resolve().parent
root = lab.parents[2]
output = Path(sys.argv[1]).resolve()
assert output.is_relative_to(Path('/tmp').resolve()) and not output.exists(), 'Use a fresh /tmp directory'
reference = json.loads((lab / 'Reference/provenance.json').read_text())
for source, digest in reference['source_sha256'].items():
    assert hashlib.sha256((lab / 'Reference' / Path(source).name).read_bytes()).hexdigest() == digest
sources = [root / 'packages/ChatUI/Sources/ChatUI' / name for name in ['ChatLayerInlineEmoji.swift', 'ChatLayerMessageTextView.swift', 'ChatLayerMessageText+Layout.swift', 'ChatMessageView.swift', 'ChatRowView.swift']]
sources += [root / 'packages/InputTextView/Sources/InputTextView/FoldingTextView.swift']
before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}
subprocess.run([sys.executable, str(root / 'tools/perflab/ChatLayerEngineLab/prepare-isolated.py'), str(output)], check=True)
assert before == {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}, 'Production changed during generation'

def declaration(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

common = output / 'Sources/FoldingViewHarness'
for name in ['CandidateBindingHarness', 'NativeBindingHarness']:
    destination = output / 'Sources' / name
    shutil.copytree(common, destination)
    dependencies = destination / 'Generated/Dependencies.swift'
    text = dependencies.read_text()
    for marker in ['struct Emoji {', 'struct PeerId {', 'struct Peer {', 'enum PlayPolicy:', 'final class InlineStickerItem:', 'final class InlineStickerItemLayer:']:
        text = text.replace(declaration(text, marker), '')
    text = text.replace('    PlaybackCounters.calls += 1\n', '').replace('    PlaybackCounters.layers += layers.count\n', '')
    text += '\ntypealias Emoji = InputView.ChatTextCustomEmojiAttribute\ntypealias Peer = InlineStickerLayer.Peer\ntypealias PeerId = InlineStickerLayer.PeerId\ntypealias PlayPolicy = InlineStickerLayer.PlayPolicy\ntypealias InlineStickerItem = InlineStickerLayer.InlineStickerItem\ntypealias InlineStickerItemLayer = InlineStickerLayer.InlineStickerItemLayer\n'
    dependencies.write_text('import InputView\nimport InlineStickerLayer\n' + text)
    shutil.copyfile(lab / 'Sources/BenchmarkDriver.swift', destination / 'BenchmarkDriver.swift')
shutil.copyfile(lab / 'Sources/InlineStickerLayer/Media.swift', output / 'Sources/InlineStickerLayer/Media.swift')

native = output / 'Sources/NativeBindingHarness/Generated'
current_body = (root / 'packages/ChatUI/Sources/ChatUI/ChatMessageView.swift').read_text()
previous_body = (lab / 'Reference/ChatMessageView.swift').read_text()
path = native / 'LayerChatTextRow.swift'
text = path.read_text()
for marker in ['    private func updateText(', '    private func updateNativeText(', '    public override func updateAnimatableContent()']:
    current = declaration(current_body, marker)
    assert current in text
    text = text.replace(current, declaration(previous_body, marker))
path.write_text(text)
previous_preparation = (lab / 'Reference/ChatLayerMessageText+Layout.swift').read_text()
methods = '\n\n'.join(declaration(previous_preparation, marker) for marker in ['    private enum AttributeKeys {', '    @inline(__always)', '    static func simpleText('])
(native / 'PlainTextPreparation.swift').write_text('import Cocoa\nimport TGUIKit\n@testable import ChatLayerEngine\n\nextension ChatLayerMessageTextPresentation {\n' + methods + '\n}\n')
current_caption = (root / 'packages/ChatUI/Sources/ChatUI/ChatRowView.swift').read_text()
previous_caption = (lab / 'Reference/ChatRowView.swift').read_text()
path = native / 'Captions.swift'
text = path.read_text()
for marker in ['    public class CaptionView {', '    public func fillCaption(', '    private final class CaptionBindingState {', '    private func updateCaptions(', '    public override func updateAnimatableContent()']:
    def transform(value):
        return value.replace('public ', '').replace('func fillCaption(', 'override func fillCaption(')
    current = transform(declaration(current_caption, marker))
    assert current in text
    text = text.replace(current, transform(declaration(previous_caption, marker)))
path.write_text(text)

(output / 'Package.swift').write_text('''// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "InlineEmojiBindingLab", platforms: [.macOS(.v10_15)], dependencies: [
    .package(path: "TGUIKit"), .package(name: "SSignalKit", path: "%s")
], targets: [
    .target(name: "TelegramCore"), .target(name: "TelegramContext"), .target(name: "InputView"),
    .target(name: "InlineStickerLayer", dependencies: ["TGUIKit", "TelegramContext", "InputView"]),
    .target(name: "InputTextView", dependencies: ["TGUIKit"]),
    .target(name: "ChatLayerEngine", dependencies: ["TGUIKit", "InputTextView", "TelegramCore", "TelegramContext", "InputView", "InlineStickerLayer", .product(name: "SwiftSignalKit", package: "SSignalKit")]),
    .target(name: "CandidateBindingHarness", dependencies: ["TGUIKit", "ChatLayerEngine", "InputTextView", "TelegramContext", "InputView", "InlineStickerLayer"]),
    .target(name: "NativeBindingHarness", dependencies: ["TGUIKit", "ChatLayerEngine", "InputTextView", "TelegramContext", "InputView", "InlineStickerLayer"]),
    .testTarget(name: "BindingTests", dependencies: ["TGUIKit", "CandidateBindingHarness", "NativeBindingHarness", "TelegramContext", "InputView", "InlineStickerLayer"])
])
''' % (root / 'submodules/telegram-ios/submodules/SSignalKit'))
tests = output / 'Tests/BindingTests'
tests.mkdir(parents=True)
for path in (lab / 'Tests').glob('*.swift'):
    shutil.copyfile(path, tests / path.name)
for name in ['TestBootstrap.swift', 'ViewSnapshot.swift']:
    shutil.copyfile(root / 'tools/perflab/ChatLayerEngineLab/Tests/FoldingViewTests' / name, tests / name)
shutil.copytree(lab / 'Reference', output / 'BindingReference')
shutil.copyfile(lab / 'README.md', output / 'BINDING-README.md')

visited = set()
inputs = set()
def collect(base):
    base = base.resolve()
    if base in visited:
        return
    visited.add(base)
    manifest = base / 'Package.swift'
    inputs.add(manifest)
    for folder in ['Sources', 'Tests']:
        inputs.update(path for path in (base / folder).rglob('*') if path.is_file())
    for parent, directories, names in os.walk(base):
        directories[:] = [name for name in directories if name not in ['.git', '.build', '.swiftpm', 'results', 'Reference', 'BindingReference', 'experiments']]
        for name in names:
            path = Path(parent) / name
            if path.suffix in ['.swift', '.m', '.mm', '.c', '.h', '.hpp', '.metal', '.modulemap'] or name == 'module.modulemap':
                inputs.add(path)
    for value in re.findall(r'\.package\([^\n]*?path: "([^"]+)"', manifest.read_text()):
        collect(base / value)
collect(output)
provenance = {'pre_inline_reference': reference, 'current_production_sha256': before, 'compiler_input_sha256': {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(inputs)}, 'template_sha256': {str(path.relative_to(lab)): hashlib.sha256(path.read_bytes()).hexdigest() for path in lab.rglob('*') if path.is_file()}, 'scope': 'Exact pre-inline body/caption/preparation methods versus current; shared current native FoldingTextView/TGUIKit; shared deterministic media/account modules; baseline must instantiate native renderer, candidate must instantiate layer renderer before timing.'}
(output / 'binding-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
assert before == {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources}, 'Production changed during snapshot'
print(output)
print(len(inputs), 'hashed compiler inputs across', len(visited), 'packages')
