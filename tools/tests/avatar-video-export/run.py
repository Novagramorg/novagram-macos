from pathlib import Path
import subprocess
import tempfile

root=Path(__file__).resolve().parents[3]
source=(root/'packages/AvatarEditorUI/Sources/AvatarEditorUI/AvatarVideoExport.swift').read_text()
with tempfile.TemporaryDirectory(prefix='avatar-video-export-') as directory:
    directory=Path(directory)
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "AvatarVideoExport", platforms: [.macOS(.v10_13)], targets: [.testTarget(name: "NativeExportTests", path: "Native"), .testTarget(name: "ControlledExportTests", path: "Controlled")])
''')
    (directory/'Native').mkdir();(directory/'Controlled').mkdir()
    (directory/'Native/AvatarVideoExport.swift').write_text(source)
    (directory/'Native/NativeExportTests.swift').write_text(Path(__file__).with_name('NativeExportTests.swift').read_text())
    (directory/'Controlled/ControlledExportTests.swift').write_text(Path(__file__).with_name('ControlledExportTests.swift').read_text().replace('__SOURCE__','\n'.join(x for x in source.splitlines() if not x.startswith('import '))))
    raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
