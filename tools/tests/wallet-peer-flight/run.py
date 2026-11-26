from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
with tempfile.TemporaryDirectory(prefix='wallet-peer-flight-') as directory:
    directory = Path(directory)
    binary = directory / 'test'
    subprocess.run(['swiftc', '-module-cache-path', str(directory / 'cache'), str(root / 'packages/WalletUI/Sources/WalletUI/WalletPeerCardFlight.swift'), str(Path(__file__).with_name('main.swift')), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
