from pathlib import Path
import hashlib
import json
import plistlib
import shutil
import subprocess
import sys

lab = Path(__file__).resolve().parent
root = lab.parents[2]
output = Path(sys.argv[1]).resolve()
assert output.is_relative_to(Path('/tmp').resolve()) and not output.exists()
assets = output / 'Assets.xcassets'
assets.mkdir(parents=True)
app = output / 'Probe.app'
resources = app / 'Contents/Resources'
resources.mkdir(parents=True)
names = ['Icon_CopyCode', 'Icon_Peer_Music_Chevron', 'Icon_Peer_Music_Waveform', 'Wallet_InfoWarning', 'Icon_SavedMessages_Premium_Tag', 'Wallet_Collectible_AddToCard']
hashes = {}
for name in names:
    source = root / 'Telegram-Mac/Assets.xcassets' / (name + '.imageset')
    shutil.copytree(source, assets / source.name)
    for path in source.rglob('*'):
        if path.is_file():
            hashes[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'local.PrecomposedTintProbe', 'CFBundleName': 'PrecomposedTintProbe', 'CFBundlePackageType': 'APPL'}))
(app / 'asset-names.txt').write_text('\n'.join(names) + '\n')
(output / 'asset-inputs.json').write_text(json.dumps(hashes, indent=2) + '\n')
subprocess.run(['xcrun', 'actool', '--compile', str(resources), '--platform', 'macosx', '--minimum-deployment-target', '10.13', '--output-format', 'human-readable-text', str(assets)], check=True)
print(app)
