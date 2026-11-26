import argparse
import json
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
source = subprocess.check_output(['git', 'show', '489ec8d18bbba43bf9bed52f31c28a35c3e6fde2:packages/TelegramMediaUtils/Sources/TelegramMediaUtils/VideoEditorThumbs.swift'], cwd=root, text=True) if args.baseline else (root/'packages/TelegramMediaUtils/Sources/TelegramMediaUtils/VideoEditorThumbs.swift').read_text()
source = '\n'.join(line for line in source.splitlines() if line not in ['import TGUIKit', 'import TelegramTheme', 'import TelegramContext', 'import TelegramUtils'])
shim = Path(__file__).with_name('Support.swift').read_text()
with tempfile.TemporaryDirectory(prefix='video-editor-thumbnails-') as directory:
    directory = Path(directory)
    dependencies = ['.package(path: '+json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))+')', '.package(path: '+json.dumps(str(root/'packages/FastBlur'))+')']
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "VideoEditorThumbnails", platforms: [.macOS(.v10_13)], dependencies: ['''+', '.join(dependencies)+'''], targets: [
.testTarget(name: "ControlledTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit"), .product(name: "FastBlur", package: "FastBlur")], path: "Controlled"),
.testTarget(name: "NativeTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit"), .product(name: "FastBlur", package: "FastBlur")], path: "Native")])
''')
    for target in ['Controlled', 'Native']:
        folder = directory/target; folder.mkdir()
        current = source
        if target == 'Controlled':
            current = current.replace('public func ', 'func ').replace('AVAssetImageGenerator', 'TestImageGenerator').replace('AVAsset', 'TestAsset').replace('AVComposition', 'TestComposition')
        (folder/'Production.swift').write_text(current)
        (folder/'Support.swift').write_text(shim)
        (folder/'Tests.swift').write_text(Path(__file__).with_name(target+'Tests.swift').read_text())
    (directory/'Native/AvatarVideoExport.swift').write_text((root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/AvatarVideoExport.swift').read_text())
    import os
    env = dict(os.environ, THUMB_BASELINE='1' if args.baseline else '0')
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4'], env=env).returncode)
