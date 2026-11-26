from pathlib import Path
import hashlib
import gzip
import json

lab = Path(__file__).resolve().parent
root = lab.parents[2]
source = root / 'packages/TGUIKit/Sources/Extensions.swift'
s = source.read_text()
original = gzip.decompress((lab / 'Reference/precomposed.swift.txt.gz').read_bytes()).decode()
metadata = json.loads((lab / 'Reference/provenance.json').read_text())
assert hashlib.sha256(original.encode()).hexdigest() == metadata['original_method_sha256']
a = s.index('    fileprivate func precomposedWithoutTintCache(')
b = s.index('\n    }', a) + 6
assert s[a:b].replace('fileprivate func precomposedWithoutTintCache(', 'func precomposed(') == original
start = s.index('private final class PrecomposedImageTintCache')
end = s.index('\npublic extension NSImage', start)
candidate = s[start:end].replace('private ', '').replace('PrecomposedImageTintCache', 'TintCache').replace('.precomposedWithoutTintCache(', '.referencePrecomposed(')
(lab / 'Tests/TintTests/Candidate.swift').write_text('import Cocoa\nimport TGUIKit\n\n' + candidate)
(lab / 'Tests/TintTests/Reference.swift').write_text('import Cocoa\nimport TGUIKit\nextension NSImage {\n' + original.replace('func precomposed(', 'func referencePrecomposed(') + '\n}\n')
(lab / 'generation.json').write_text(json.dumps({'production_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'candidate_sha256': hashlib.sha256(candidate.encode()).hexdigest(), 'original_sha256': metadata['original_method_sha256']}, indent=2) + '\n')
