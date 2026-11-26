from pathlib import Path
import hashlib
import gzip
import json

lab = Path(__file__).resolve().parent
source = lab / 'Reference/quote-mask-layout.swift.txt.gz'
captured = gzip.decompress(source.read_bytes())
assert hashlib.sha256(captured).hexdigest() == json.loads((lab / 'Reference/quote-mask-provenance.json').read_text())['captured_sha256']
reference = captured.decode().replace('public ', '').replace('FoldingTextLayout', 'ReferenceMaskFoldingTextLayout')
reference = reference.replace('private func generateMaskImage(size: NSSize, y: CGFloat)', 'func referenceMaskImage(size: NSSize, y: CGFloat, scale: CGFloat)')
reference = reference.replace('generateImage(size, rotatedContext:', 'generateImage(size, scale: scale, rotatedContext:')
reference = reference.replace('generateMaskImage(size: NSMakeSize(size.width, size.height - 5), y: text.lines[0].frame.maxY + 2)', 'referenceMaskImage(size: NSMakeSize(size.width, size.height - 5), y: text.lines[0].frame.maxY + 2, scale: System.backingScale)')
output = lab / 'Sources/FoldingViewHarness/Generated'
(output / 'ReferenceMask.swift').write_text('import Cocoa\nimport TGUIKit\nimport TelegramContext\n' + reference)
p = output / 'Current.swift'
s = p.read_text()
a = s.index('private final class FoldingQuoteMaskCache {')
b = s.index('\nprivate func generateMaskImage(', a)
s = s[:a] + s[a:b].replace('private ', '') + s[b:]
p.write_text(s)
