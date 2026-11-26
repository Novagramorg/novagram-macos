from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/ChatUI/Sources/ChatUI/ChatController.swift').read_text()
action = (root / 'packages/ChatUI/Sources/ChatUI/ChatDeferredSendAction.swift').read_text().split('\nfunc chatHasSameDeferredSendState')[0]
fixture = Path(__file__).with_name('AttachmentTests.swift').read_text().replace('__ACTION__', action)
for route, following, call, indent, placeholder in [
    ('attachFile', 'attachPhotoOrVideo', 'filePanel(', 24, '__FILES__'),
    ('attachPhotoOrVideo', 'attachPicture', 'filePanel(', 20, '__PHOTOS__'),
    ('attachPicture', 'attachLocation', 'pickImage(', 16, '__IMAGE__'),
]:
    start = source.index('        chatInteraction.' + route + ' =')
    end = source.index('        chatInteraction.' + following + ' =', start)
    route_source = source[start:end]
    declarations = '\n'.join(line for line in route_source.splitlines() if 'let journey =' in line or 'let selectionAction =' in line)
    start = route_source.index(call)
    closing = '\n' + (' ' * indent) + '})'
    end = route_source.index(closing, start) + len(closing)
    fixture = fixture.replace(placeholder, declarations + '\n' + route_source[start:end])
with tempfile.TemporaryDirectory(prefix='attachment-acquisition-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "AttachmentAcquisition", targets: [.testTarget(name: "AttachmentAcquisitionTests", path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/AttachmentTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
