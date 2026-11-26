import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--release', action='store_true')
parser.add_argument('--benchmark', action='store_true')
parser.add_argument('--sanitize', action='store_true')
parser.add_argument('--results', type=Path)
args = parser.parse_args()
lab = Path(__file__).resolve().parent
root = lab.parents[2]
source = root / 'packages/ChatUI/Sources/ChatUI/ChatTextFontRanges.swift'
callsite = root / 'packages/ChatUI/Sources/ChatUI/ChatMessageItem.swift'
assert 'chatForEachBoldItalicRange(bold: boldRanges, italic: italicRanges)' in callsite.read_text()
assert 'for boldRange in boldRanges' not in callsite.read_text()
with tempfile.TemporaryDirectory(prefix='chat-text-font-lab-') as directory:
    scratch = Path(directory)
    executable = scratch / 'tests'
    command = ['xcrun', 'swiftc', '-O' if args.release or args.benchmark else '-Onone', '-module-cache-path', str(scratch / 'ModuleCache')]
    if args.sanitize:
        command += ['-sanitize=address']
    command += [str(source), str(lab / 'Reference.swift'), str(lab / 'main.swift'), '-o', str(executable)]
    subprocess.run(command, check=True)
    environment = os.environ.copy()
    environment['FONT_BENCH_RESULTS'] = str(scratch / 'results.json')
    subprocess.run([str(executable)] + (['--benchmark'] if args.benchmark else []), env=environment, check=True)
    if args.results:
        result = json.loads((scratch / 'results.json').read_text())
        result['production_sha256'] = hashlib.sha256(source.read_bytes()).hexdigest()
        result['scope'] = 'Bold/italic overlap application using real AppKit attributed strings; excludes entity parsing, other formatting, text measurement, and chat UI.'
        args.results.write_text(json.dumps(result, indent=2) + '\n')
