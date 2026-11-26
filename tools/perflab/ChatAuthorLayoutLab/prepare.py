from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
baseline = 'ba81323e5'
path = 'packages/ChatUI/Sources/ChatUI/ChatRowItem.swift'
original = subprocess.check_output(['git', 'show', baseline + ':' + path], cwd=root, text=True)
current = (root / path).read_text()

def block(source, marker, include_else=False):
    start = source.index(marker, source.index('    public override func makeSize('))
    cursor = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    if include_else:
        assert source[cursor:].startswith(' else {')
        cursor += len(' else {')
        depth = 1
        while depth:
            depth += (source[cursor] == '{') - (source[cursor] == '}')
            cursor += 1
    return source[start:cursor]

def generate(name, source):
    forward = block(source, '        if let forwardNameLayout = forwardNameLayout')
    author = block(source, '        if !canFillAuthorName, let replyModel = replyModel', True)
    return 'final class ' + name + ': AuthorEnvironment {\n    func measureForward(_ width: CGFloat, widthForContent: CGFloat) {\n' + forward + '\n    }\n    func measureAuthor(_ widthForContent: CGFloat, cachedRightSize: NSSize) {\n' + author + '\n    }\n}\n'

output = 'import Cocoa\nimport TGUIKit\n' + generate('ReferenceAuthor', original) + generate('CandidateAuthor', current)
(lab / 'Tests/AuthorTests/Generated.swift').write_text(output)
(lab / 'generation.json').write_text(json.dumps({'baseline': baseline, 'original_sha256': hashlib.sha256(original.encode()).hexdigest(), 'candidate_sha256': hashlib.sha256(current.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest()}, indent=2) + '\n')
