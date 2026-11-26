from pathlib import Path
import gzip
import hashlib
import json
import shutil
import subprocess
import sys

lab = Path(__file__).resolve().parent
root = lab.parents[2]
output = Path(sys.argv[1]).resolve()
assert output.is_relative_to(Path('/tmp').resolve()) and not output.exists()
metadata = json.loads((lab / 'provenance.json').read_text())
subprocess.run([sys.executable, str(root / 'tools/perflab/ChatLayerEngineLab/prepare-isolated.py'), str(output)], check=True)
for name in ['ChatLayerTextNode.swift', 'ChatLayerMessageText.swift']:
    target = output / 'Sources/ChatLayerEngine/Generated' / name
    assert hashlib.sha256(target.read_bytes()).hexdigest() == metadata['sha256']['Reference/' + name], name
    candidate = gzip.decompress((lab / 'Candidate' / (name + '.gz')).read_bytes())
    assert hashlib.sha256(candidate).hexdigest() == metadata['sha256']['Candidate/' + name], name
    target.write_bytes(candidate)
wrapper = output / 'Sources/InputTextView/Generated/QuoteWrapper.swift'
with wrapper.open('a') as stream:
    stream.write('\npublic func updateCandidateFoldingWrapper(_ view: View, layout: FoldingTextLayout.ViewLayout, transition: ContainedViewLayoutTransition) {\n    (view as! CandidateWrapperView).update(layout, isRevealed: layout.isRevealed, context: ReferenceContext(), transition: transition)\n}\n')
shutil.copy2(lab / 'Tests/FoldingTransitionTests.swift', output / 'Tests/ChatLayerEngineTests/FoldingTransitionTests.swift')
print(output)
