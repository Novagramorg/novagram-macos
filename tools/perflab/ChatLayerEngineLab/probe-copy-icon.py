from pathlib import Path
import json
import plistlib
import shutil
import subprocess
import sys
import tempfile

lab = Path(__file__).resolve().parent
root = lab.parents[2]
with tempfile.TemporaryDirectory(prefix='QuoteIconProbe-') as temporary:
    directory = Path(temporary)
    app = directory / 'Probe.app'
    resources = app / 'Contents/Resources'
    resources.mkdir(parents=True)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'local.QuoteIconProbe', 'CFBundleName': 'QuoteIconProbe', 'CFBundlePackageType': 'APPL'}))
    assets = directory / 'Assets.xcassets'
    assets.mkdir()
    shutil.copytree(root / 'Telegram-Mac/Assets.xcassets/Icon_CopyCode.imageset', assets / 'Icon_CopyCode.imageset')
    subprocess.run(['xcrun', 'actool', '--compile', str(resources), '--platform', 'macosx', '--minimum-deployment-target', '10.13', '--output-format', 'human-readable-text', str(assets)], check=True, capture_output=True)
    result = subprocess.check_output(['swift', '-module-cache-path', str(directory / 'ModuleCache'), str(lab / 'probe-copy-icon.swift'), str(app)], text=True)
    data = json.loads(result)
    Path(sys.argv[1]).write_text(json.dumps(data, indent=2) + '\n')
    print(json.dumps(data))
