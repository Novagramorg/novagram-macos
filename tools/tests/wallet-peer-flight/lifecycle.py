from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/WalletUI/Sources/WalletUI/WalletPeerBalanceController.swift').read_text()
start = source.index('private final class WalletPeerBalanceSource')
end = source.index('@available(macOS 10.15, *)\nprivate final class WalletPeerBalanceController', start)
fixture = Path(__file__).with_name('lifecycle.swift').read_text()
with tempfile.TemporaryDirectory(prefix='wallet-flight-lifecycle-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'packages/TGUIKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "FlightLifecycleTests", platforms: [.macOS(.v10_15)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.executableTarget(name: "FlightLifecycleTests", dependencies: ["TGUIKit"], path: "Sources")])
''')
    (directory / 'Sources').mkdir()
    (directory / 'Sources/main.swift').write_text(fixture.replace('__VIEW__', source[start:end]))
    (directory / 'Sources/WalletPeerCardFlight.swift').write_text((root / 'packages/WalletUI/Sources/WalletUI/WalletPeerCardFlight.swift').read_text())
    subprocess.run(['swift', 'run', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4', 'FlightLifecycleTests'], check=True)
