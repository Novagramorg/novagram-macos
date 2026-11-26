from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
path = 'packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatAccessoryModel.swift'
baseline = '7a9252645'
original = subprocess.check_output(['git', 'show', baseline + ':' + path], cwd=root, text=True)
current = (root / path).read_text()

def block(source, marker):
    start = source.index(marker, source.index('public class ChatAccessoryView'))
    cursor = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    if source[cursor:].startswith(' else {'):
        cursor += len(' else {')
        depth = 1
        while depth:
            depth += (source[cursor] == '{') - (source[cursor] == '}')
            cursor += 1
    return source[start:cursor]

def generate(name, source):
    properties = '\n'.join(line for line in source.splitlines() if any(marker in line for marker in ['private var text_inlineStickerItemViews:', 'private var header_inlineStickerItemViews:', 'private let contentObserver', 'private var contentObserver', 'private var isLite:']))
    message = block(source, '        if let message = model.message, let view = self.textView')
    header = block(source, '        if let textLayout = model.header')
    tail_start = source.index('        let transition: ContainedViewLayoutTransition', source.index('public class ChatAccessoryView'))
    tail_end = source.index('\n    }', tail_start)
    tail = source[tail_start:tail_end]
    methods = '\n'.join(block(source, marker) for marker in ['    public override func viewDidMoveToWindow()', '    public override func viewDidMoveToSuperview()', '    @objc func updateAnimatableContent()', '    private func updateListeners()', '    public func updateInlineStickers(', '    deinit {'])
    return 'class ' + name + ': AccessoryBase {\n' + properties + '\n    var observerForTesting: AnimatableContentTokenObserver? { contentObserver }\n    var headerLayers: [InlineStickerItemLayer] { Array(header_inlineStickerItemViews.values) }\n    var messageLayers: [InlineStickerItemLayer] { Array(text_inlineStickerItemViews.values) }\n    func apply(_ model: FixtureModel, animated: Bool = false) {\n        headerView.update(model.header)\n        textView?.update(model.message)\n' + message + '\n' + header + '\n' + tail + '\n    }\n' + methods + '\n}\n'

lifecycle_candidate = subprocess.check_output(['git', 'show', '9953e0ace:' + path], cwd=root, text=True)
output = 'import Cocoa\nimport TGUIKit\n' + generate('ReferenceAccessory', original) + generate('CandidateAccessory', lifecycle_candidate)
(lab / 'Tests/AccessoryTests/Generated.swift').write_text(output)
helpers = {}
for name in ['InlineStickerPlayback.swift', 'InlineStickerKeyCollection.swift']:
    helper = root / 'packages/InlineStickerLayer/Sources/InlineStickerLayer' / name
    data = helper.read_bytes()
    (lab / 'Tests/AccessoryTests' / name).write_bytes(data)
    helpers[str(helper.relative_to(root))] = hashlib.sha256(data).hexdigest()
(lab / 'generation.json').write_text(json.dumps({'baseline': baseline, 'original_sha256': hashlib.sha256(original.encode()).hexdigest(), 'candidate_revision': '9953e0ace', 'candidate_sha256': hashlib.sha256(lifecycle_candidate.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest(), 'helpers': helpers}, indent=2) + '\n')

full_baseline = subprocess.check_output(['git', 'show', '9953e0ace:' + path], cwd=root, text=True)
full_source = ''
for name, source in [('NativeAccessoryView', full_baseline), ('ChatAccessoryView', current)]:
    stars = source[source.index('private final class StarsView'):source.index('public class ChatAccessoryView')]
    view = block(source, 'public class ChatAccessoryView')
    full_source += stars + view.replace('public class ChatAccessoryView', 'class ' + name).replace('public ', '') + '\n'
    if name == 'NativeAccessoryView':
        full_source = full_source.replace('StarsView', 'NativeStarsView')
for name in ['NativeAccessoryView', 'ChatAccessoryView']:
    full_source += '\nextension ' + name + ' {\n' + 'var observerForTesting: AnimatableContentTokenObserver? { contentObserver }\nvar headerLayers: [InlineStickerItemLayer] { Array(header_inlineStickerItemViews.values) }\nvar messageLayers: [InlineStickerItemLayer] { Array(text_inlineStickerItemViews.values) }\nvar infoForTesting: ImageButton? { infoButton }\nfunc patternForTesting(_ image: CGImage?) { updatePatternLayerImages(image) }\n'
    if name == 'NativeAccessoryView':
        full_source += 'var headerFrame: CGRect { headerView.frame }\nvar messageFrame: CGRect { textView?.frame ?? .zero }\nvar pollFrame: CGRect? { pollIconView?.frame }\nvar quoteFrame: CGRect? { quoteView?.frame }\n'
    else:
        full_source += 'var headerFrame: CGRect { headerContent.frame }\nvar messageFrame: CGRect { messageContent.frame }\nvar pollFrame: CGRect? { pollIconLayer?.frame }\nvar quoteFrame: CGRect? { quoteLayer?.frame }\n'
    full_source += '}\n'
(lab / 'Tests/AccessoryTests/GeneratedFull.swift').write_text('import Cocoa\nimport TGUIKit\nimport ColorPalette\n' + full_source)
content = current[current.index('final class ChatAccessoryTextContent'):current.index('private final class StarsView')]
(lab / 'Tests/AccessoryTests/GeneratedTextContent.swift').write_text('import Cocoa\nimport TGUIKit\n' + content)
(lab / 'full-generation.json').write_text(json.dumps({'baseline': '9953e0ace', 'source_sha256': {path: hashlib.sha256(current.encode()).hexdigest()}, 'full_generated_sha256': hashlib.sha256(full_source.encode()).hexdigest(), 'transforms': ['replace native baseline class names', 'remove external imports and public visibility from enclosing accessory views', 'append read-only test accessors and pattern-image injection'], 'scope': 'Complete production ChatAccessoryView and StarsView plus exact text/icon content helpers; account, media, model and theme services are stand-ins.'}, indent=2) + '\n')
