from pathlib import Path
import gzip
import hashlib
import json
import shutil
import sys

lab = Path(__file__).resolve().parent
output = Path(sys.argv[1]).resolve()
assert output.is_relative_to(Path('/tmp').resolve()) and not output.exists()
shutil.copytree(lab / 'Standalone', output)
for module, variant in [('PathReference', 'original'), ('PathCandidate', 'candidate')]:
    destination = output / 'Sources' / module
    destination.mkdir(parents=True)
    for name in ['PathDataReader.swift', 'ShimmerLayer.swift', 'StickerThumbnailPath.swift']:
        selected = 'original' if name == 'StickerThumbnailPath.swift' else variant
        suffix = '.gz' if selected == 'original' else '.candidate.gz'
        source = gzip.decompress((lab / 'Reference' / (name + suffix)).read_bytes())
        metadata = json.loads((lab / 'Reference' / (name + '.provenance.json')).read_text())
        assert hashlib.sha256(source).hexdigest() == metadata[selected + '_sha256']
        if name == 'ShimmerLayer.swift':
            source = b'import Cocoa\n' + source[source.index(b'open class PathSegment: Equatable {'):]
            name = 'PathSegment.swift'
        (destination / name).write_bytes(source)
print(output)
