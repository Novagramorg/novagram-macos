from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/FilePanels/Sources/FilePanels/PicturePicker.swift').read_text()
source = source[source.index('fileprivate class PickerObserver'):].replace('public func', 'func')
fixture = Path(__file__).with_name('PickerTests.swift').read_text().replace('__PICKER__', source)
with tempfile.TemporaryDirectory(prefix='picture-picker-context-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "PicturePickerContext", platforms: [.macOS(.v10_15)], targets: [.testTarget(name: "PicturePickerContextTests", path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/PickerTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
