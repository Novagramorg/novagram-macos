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
metadata = json.loads((lab / 'Reference/StickerThumbnailPath.swift.provenance.json').read_text())
for module, variant in [('DecodeReference', 'original'), ('DecodeCandidate', 'candidate')]:
    suffix = '.gz' if variant == 'original' else '.candidate.gz'
    source = gzip.decompress((lab / 'Reference' / ('StickerThumbnailPath.swift' + suffix)).read_bytes())
    assert hashlib.sha256(source).hexdigest() == metadata[variant + '_sha256']
    inspection = 'baseline' if variant == 'original' else 'candidate'
    destination = output / 'Sources' / module
    destination.mkdir(parents=True)
    (destination / 'StickerThumbnailPath.swift').write_bytes(source + (lab / ('decoder.' + inspection + '.inspection.txt')).read_bytes())
print(output)
