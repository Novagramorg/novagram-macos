from pathlib import Path
import gzip
import hashlib
import json
import re

lab = Path(__file__).resolve().parent
root = lab.parents[2]
source = root / 'packages/TGUIKit/Sources/DrawingContext.swift'
s = source.read_text()
original = gzip.decompress((lab / 'Reference/drawing-context.swift.txt.gz').read_bytes()).decode()
metadata = json.loads((lab / 'Reference/provenance.json').read_text())
assert hashlib.sha256(original.encode()).hexdigest() == metadata['original_sha256']
a = s.index('public class DrawingContext {')
b = s.index('\npublic enum ParsingError', a)
current = s[a:b]
expected = original
start = expected.index('    public init(')
end = expected.index('    public func generateDisplayImage()', start)
part = expected[start:end].replace('        self.bytesPerRow = DeviceGraphicsContextSettings.shared.', '        let settings = DeviceGraphicsContextSettings.shared\n        self.bytesPerRow = settings.')
part = part.replace('DeviceGraphicsContextSettings.shared.opaqueBitmapInfo', 'settings.opaqueBitmapInfo').replace('DeviceGraphicsContextSettings.shared.bitsPerComponent', 'settings.bitsPerComponent').replace('DeviceGraphicsContextSettings.shared.colorSpace', 'settings.colorSpace')
expected = expected[:start] + part + expected[end:]
expected = expected.replace('space: DeviceGraphicsContextSettings.shared.colorSpace,', 'space: self.context.colorSpace!,')
assert current.strip() == expected.strip(), 'Unexpected changes to the drawing-context implementation'
(lab / 'generation.json').write_text(json.dumps({'production_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'original_sha256': metadata['original_sha256']}, indent=2) + '\n')
