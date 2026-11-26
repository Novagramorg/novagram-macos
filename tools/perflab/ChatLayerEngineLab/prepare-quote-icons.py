from pathlib import Path
import base64
import gzip
import hashlib
import json

lab = Path(__file__).resolve().parent
metadata = json.loads((lab / 'Reference/quote-icon-provenance.json').read_text())
captured = gzip.decompress((lab / 'Reference/quote-icon-painter.swift.txt.gz').read_bytes())
assert hashlib.sha256(captured).hexdigest() == metadata['captured_sha256']
reference = captured.decode().replace('public ', '').replace('FoldingTextQuoteLayer', 'ReferenceIconQuoteLayer')
output = lab / 'Sources/FoldingViewHarness/Generated'
p = output / 'Current.swift'
s = p.read_text()
asset_end = reference.index('final class ReferenceIconQuoteLayer')
assert reference[:asset_end].strip() in s, 'The unchanged quote resource must match the captured original'
reference = 'private let quoteIcon = referenceSharedQuoteIcon()\n\n' + reference[asset_end:]
(output / 'ReferenceIcon.swift').write_text('import Cocoa\nimport TGUIKit\n' + reference)
a = s.index('    private final class CopyIconCache {')
b = s.index('    var blockQuotes:', a)
s = s[:a] + s[a:b].replace('private ', '') + s[b:]
p.write_text(s + '\nfunc referenceSharedQuoteIcon() -> CGImage { quoteIcon }\n')
fixture = 'import Cocoa\n\nfunc makeRealCopyIconFixture() -> NSImage {\n    let image = NSImage(size: NSSize(width: 16, height: 16))\n'
for name, expected in metadata['asset_fixture_sha256'].items():
    data = (lab / 'Reference' / name).read_bytes()
    assert hashlib.sha256(data).hexdigest() == expected
    encoded = base64.b64encode(data).decode()
    fixture += '    if let data = Data(base64Encoded: "' + encoded + '"), let representation = NSBitmapImageRep(data: data) {\n        representation.size = image.size\n        image.addRepresentation(representation)\n    }\n'
fixture += '    return image\n}\n'
(output / 'RealCopyIconFixture.swift').write_text(fixture)
