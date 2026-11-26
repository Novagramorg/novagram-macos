from pathlib import Path
import hashlib
import json
import tarfile

lab = Path(__file__).resolve().parent
metadata = json.loads((lab / 'Reference/live-folding-baseline.json').read_text())
with tarfile.open(lab / 'Reference/live-folding-baseline.tar.gz') as archive:
    for entry in archive.getmembers():
        assert entry.isfile() and entry.name in metadata['source_sha256']
        data = archive.extractfile(entry).read()
        assert hashlib.sha256(data).hexdigest() == metadata['source_sha256'][entry.name]
        relative = Path(entry.name)
        assert relative.parts[0] in ['ChatLayerEngine', 'FoldingViewHarness']
        target = lab / 'Sources' / (relative.parts[0] + 'Baseline') / Path(*relative.parts[1:])
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(data.decode().replace('ChatLayerEngine', 'ChatLayerEngineBaseline'))
