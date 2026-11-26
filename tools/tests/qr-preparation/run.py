from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source_path = 'packages/QrStudioUI/Sources/QrStudioUI/QrStudioController.swift'
source = (root / source_path).read_text()
start = source.index('    private var isLookReady: Bool {')
end = source.index('    private func revealIfReady()', start)
readiness = source[start:end].replace('private var isLookReady', 'var isLookReady')
fixture = Path(__file__).with_name('main.swift').read_text()
with tempfile.TemporaryDirectory(prefix='qr-preparation-') as directory:
    directory = Path(directory)
    path = directory / 'main.swift'
    path.write_text(fixture.replace('__READINESS__', readiness))
    binary = directory / 'test'
    subprocess.run(['swiftc', '-module-cache-path', str(directory / 'cache'), str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
