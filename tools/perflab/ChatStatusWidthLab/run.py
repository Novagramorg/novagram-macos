import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--release', action='store_true')
parser.add_argument('--benchmark', action='store_true')
parser.add_argument('--sanitize', action='store_true')
parser.add_argument('--results', type=Path)
args = parser.parse_args()
lab = Path(__file__).resolve().parent
root = lab.parents[2]
source = root / 'packages/ChatUI/Sources/ChatUI/ChatRightView.swift'
text = source.read_text()
start = text.index('    public struct Frames {')
end = text.index('\n    private var visualEffect:', start)
production = text[start:end].strip()
reference = (lab / 'Reference.swift').read_text()
fields = re.findall(r'public private\(set\) var (\w+):\s*NSRect\?', production)
assert len(fields) == 18
assert re.findall(r'public private\(set\) var (\w+):\s*NSRect\?', reference) == fields
assert 'public private(set) var width: CGFloat = 0' in production
assert production.count('self.width = measureWidth()') == 1
callsite = (root / 'packages/ChatUI/Sources/ChatUI/ChatRowItem.swift').read_text()
assert 'NSMakeSize(frames.width, rightHeight)' in callsite
assert 'self.rightFrames = isIncomingTypingDraft ? nil : ChatRightView.Frames(self,' in callsite
extensions = (root / 'packages/TGUIKit/Sources/Extensions.swift').read_text()
size_bounds = 'var bounds: CGRect {\n        return NSMakeRect(0, 0, width, height)\n    }'
assert size_bounds in extensions
focus_start = extensions.index('    func focus(_ size:NSSize) -> NSRect {', extensions.index('var center: CGPoint'))
focus_end = extensions.index('\n    func focusX(', focus_start)
geometry = 'extension CGSize {\n' + size_bounds + '\n}\nextension CGRect {\n' + extensions[focus_start:focus_end] + '\n}\n'


def with_fixtures(value, candidate):
    fixture = '\n    init(rectangles: [CGRect?], overlay: Bool) {\n        self.isStateOverlay = overlay\n'
    fixture += ''.join(f'        self.{field} = rectangles[{index}]\n' for index, field in enumerate(fields))
    if candidate:
        fixture += '        self.width = measureWidth()\n'
    fixture += '    }\n    var rectangles: [CGRect?] { [' + ', '.join('self.' + field for field in fields) + '] }\n'
    end = value.rindex('}')
    return value[:end] + fixture + value[end:]


with tempfile.TemporaryDirectory(prefix='chat-status-width-lab-') as directory:
    scratch = Path(directory)
    (scratch / 'Frames.swift').write_text('import Cocoa\n' + with_fixtures(production, True))
    (scratch / 'ReferenceFrames.swift').write_text(with_fixtures(reference, False))
    (scratch / 'Geometry.swift').write_text('import Cocoa\n' + geometry)
    executable = scratch / 'tests'
    command = ['xcrun', 'swiftc', '-O' if args.release or args.benchmark else '-Onone', '-module-cache-path', str(scratch / 'ModuleCache')]
    if args.sanitize:
        command += ['-sanitize=address']
    command += [str(scratch / name) for name in ['Frames.swift', 'ReferenceFrames.swift', 'Geometry.swift']]
    command += [str(lab / name) for name in ['Environment.swift', 'main.swift']]
    command += ['-o', str(executable)]
    subprocess.run(command, check=True)
    environment = os.environ.copy()
    environment['WIDTH_BENCH_RESULTS'] = str(scratch / 'results.json')
    subprocess.run([str(executable)] + (['--benchmark'] if args.benchmark else []), env=environment, check=True)
    if args.results:
        result = json.loads((scratch / 'results.json').read_text())
        result['production_frames_sha256'] = hashlib.sha256(production.encode()).hexdigest()
        result['scope'] = 'Actual ChatRightView.Frames construction and width access with supplied text/icon sizes. Excludes text measurement, rendering, message creation, and full chat layout.'
        args.results.write_text(json.dumps(result, indent=2) + '\n')
