from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/ChatUI/Sources/ChatUI/ChatController.swift').read_text()
start = source.index('    public override func draggingItems(for pasteboard:NSPasteboard)')
end = source.index('    override public var isOpaque:', start)
method = source[start:end].replace('public override func', 'func', 1)
action = (root / 'packages/ChatUI/Sources/ChatUI/ChatDeferredSendAction.swift').read_text().split('\nfunc chatHasSameDeferredSendState')[0]
fixture = Path(__file__).with_name('DropTests.swift').read_text().replace('__DROP__', method).replace('__ACTION__', action)
with tempfile.TemporaryDirectory(prefix='media-drop-acquisition-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "MediaDropAcquisition", targets: [.testTarget(name: "MediaDropAcquisitionTests", path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/DropTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
