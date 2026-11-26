from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/PaymentsUI/Sources/PaymentsUI/PaymentWebInteractionController.swift').read_text()
fixture = Path(__file__).with_name('WebContextTests.swift').read_text()
start = source.index('    public override func viewWillDisappear(')
end = source.index('    public override var defaultBarTitle:', start)
fixture = fixture.replace('__DISAPPEAR__', source[start:end])
start = source.index('    private func handleScriptMessage(')
fixture = fixture.replace('__CALLBACKS__', source[start:source.rfind('}')])
with tempfile.TemporaryDirectory(prefix='payment-web-context-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "PaymentWebContext", targets: [.testTarget(name: "PaymentWebContextTests", path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/WebContextTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
