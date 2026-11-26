from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/ChatUI/Sources/ChatUI/ChatMessageDateHeader.swift').read_text()
start = source.index('func chatDateMessageRange(')
end = source.index('\npublic class ChatDateStickItem', start)
tests = Path(__file__).with_name('DateRangeTests.swift').read_text()
with tempfile.TemporaryDirectory(prefix='chat-date-hover-') as directory:
    path = Path(directory) / 'main.swift'
    path.write_text('import Foundation\n' + source[start:end] + tests)
    subprocess.run(['swift', '-module-cache-path', str(Path(directory) / 'cache'), str(path)], check=True)
