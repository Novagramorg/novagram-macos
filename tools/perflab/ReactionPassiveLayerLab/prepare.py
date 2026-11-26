from pathlib import Path
import hashlib
import json
import re
import shutil
import sys
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
output = Path(sys.argv[1]).resolve()
assert output.is_relative_to(Path('/tmp').resolve()), 'Use a fresh directory under /tmp'
assert not output.exists(), 'Output already exists'
shutil.copytree(lab, output, ignore=shutil.ignore_patterns('.build', '.swiftpm', 'results', '__pycache__'))
source_hashes = {}
packages = {}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def capture(source, target):
    data = source.read_bytes()
    source_hashes[str(source.relative_to(root))] = hashlib.sha256(data).hexdigest()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(data)

pattern = re.compile(r'\.package\([^)]*?path:\s*"([^"]+)"[^)]*\)', re.S)

def freeze_package(source):
    source = source.resolve()
    assert source.is_relative_to(root)
    if source in packages:
        return packages[source]
    target = output / 'Dependencies' / source.name
    assert target not in packages.values(), 'Duplicate package directory name'
    packages[source] = target
    for path in source.rglob('*'):
        if path.is_file() and not any(part in {'.build', '.git', '.swiftpm', '__pycache__'} for part in path.relative_to(source).parts):
            capture(path, target / path.relative_to(source))
    manifest = (source / 'Package.swift').read_text()
    manifest_code = '\n'.join(line for line in manifest.splitlines() if not line.lstrip().startswith('//'))
    assert re.search(r'\.package\([^)]*\burl\s*:', manifest_code, re.S) is None, 'Network dependency must be frozen explicitly'
    replacements = {}
    for match in pattern.finditer(manifest):
        relative = match.group(1)
        replacements[relative] = freeze_package(source / relative)
    rewritten = pattern.sub(lambda match: match.group(0).replace('"' + match.group(1) + '"', '"' + str(replacements[match.group(1)]) + '"'), manifest)
    (target / 'Package.swift').write_text(rewritten)
    return target

kit = freeze_package(root / 'packages/TGUIKit')
helper = root / 'packages/ChatUI/Sources/ChatUI/ChatReactionTextLayer.swift'
reaction = root / 'packages/ChatUI/Sources/ChatUI/ChatReactionsView.swift'
source_hashes[str(helper.relative_to(root))] = digest(helper)
source_hashes[str(reaction.relative_to(root))] = digest(reaction)
subprocess.run([sys.executable, str(lab / 'generate.py'), str(root), str(output)], check=True)
manifest = output / 'Package.swift'
assert digest(manifest) == digest(lab / 'Package.swift'), 'Lab manifest changed during snapshot'
manifest.write_text(manifest.read_text().replace('../../../packages/TGUIKit', str(kit)))
for source, expected in source_hashes.items():
    assert digest(root / source) == expected, 'Source changed during snapshot: ' + source
for source in lab.rglob('*'):
    if source.is_file() and not any(part in {'.build', '.swiftpm', 'results', '__pycache__'} for part in source.relative_to(lab).parts):
        source_hashes[str(source.relative_to(root))] = digest(source)
        if source.name != 'Package.swift':
            assert digest(output / source.relative_to(lab)) == digest(source)
for source, expected in source_hashes.items():
    assert digest(root / source) == expected, 'Source changed during snapshot: ' + source
frozen_hashes = {str(path.relative_to(output)): digest(path) for path in output.rglob('*') if path.is_file()}
(output / 'provenance.json').write_text(json.dumps({'production_helper_sha256': digest(helper), 'source_sha256': source_hashes, 'frozen_sha256': frozen_hashes, 'scope': 'Exact reaction text layer and extracted passive bindings plus real TGUIKit and local dependencies; icon stand-in; no media, avatar fetches or account actions.'}, indent=2, sort_keys=True) + '\n')
print(output)
