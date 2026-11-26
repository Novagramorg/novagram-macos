from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
baseline = '84be5dd1a'
path = 'packages/ChatUI/Sources/ChatUI/ChatRowItem.swift'
original = subprocess.check_output(['git', 'show', baseline + ':' + path], cwd=root, text=True)
current = (root / path).read_text()

def block(source, marker):
    start = source.index(marker, source.index('    public override func makeSize('))
    cursor = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]

def generate(name, source):
    start = source.index('        let cachedContentOffset = contentOffset', source.index('    public override func makeSize('))
    end = source.index('        self.rightFrames =', start)
    counters = source[start:end]
    header = block(source, '        if (forwardType == .FullHeader')
    header_end = source.index(header) + len(header)
    remaining = source[header_end:]
    assert remaining.startswith(' else {')
    header += remaining[:remaining.index('}') + 1]
    badge = block(source, '        if let guestChatBadge = guestChatBadge')
    return 'final class ' + name + ': MetadataEnvironment {\n    func measureCounters(_ width: CGFloat) {\n' + counters + '\n    }\n    func measureHeader() {\n' + header + '\n    }\n    func measureBadge(_ widthForContent: CGFloat) {\n' + badge + '\n    }\n}\n'

output = 'import Cocoa\nimport TGUIKit\n' + generate('ReferenceMetadata', original) + generate('CandidateMetadata', current)
(lab / 'Tests/MetadataTests/Generated.swift').write_text(output)
(lab / 'generation.json').write_text(json.dumps({'baseline': baseline, 'original_sha256': hashlib.sha256(original.encode()).hexdigest(), 'candidate_sha256': hashlib.sha256(current.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest()}, indent=2) + '\n')
