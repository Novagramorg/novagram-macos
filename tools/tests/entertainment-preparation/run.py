from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/EntertainmentUI/Sources/EntertainmentUI/EntertainmentViewController.swift').read_text()
start = source.index('    public func prepareForPresentation()')
end = source.index('    public func update(with chatInteraction:', start)
fixture = Path(__file__).with_name('main.swift').read_text()
with tempfile.TemporaryDirectory(prefix='entertainment-preparation-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "PreparationTests", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.executableTarget(name: "PreparationTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Sources")])
''')
    (directory / 'Sources').mkdir()
    (directory / 'Sources/main.swift').write_text(fixture.replace('__PREPARATION__', source[start:end]))
    subprocess.run(['swift', 'run', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4', 'PreparationTests'], check=True)
