from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/ChatUI/Sources/ChatUI/ChatInputActionsView.swift').read_text()
start = source.index('    private func addHoverObserver()')
end = source.index('    public func toggleKeyboard()', start)
handlers = source[start:end]
split = (root / 'packages/TGUIKit/Sources/TGSplitView.swift').read_text()
start = split.index('    public func additionalWidthForTrailing(')
end = split.index('    public func canShowTrailing(', start)
width = split[start:end]
fixture = Path(__file__).with_name('main.swift').read_text()
with tempfile.TemporaryDirectory(prefix='entertainment-input-') as directory:
    directory = Path(directory)
    path = directory / 'main.swift'
    path.write_text(fixture.replace('__HANDLERS__', handlers).replace('__WIDTH__', width))
    binary = directory / 'test'
    subprocess.run(['swiftc', '-module-cache-path', str(directory / 'cache'), str(path), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
