import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--scratch-path', default='/tmp/ChatLayerEngineLab-release')
parser.add_argument('--output', type=Path, default=Path('/tmp/chat-caption-memory-results'))
parser.add_argument('--runs', type=int, default=5)
args = parser.parse_args()
if args.runs < 1:
    parser.error('--runs must be positive')
args.output.mkdir(parents=True, exist_ok=True)
lab = Path(__file__).resolve().parent
samples = {'native': [], 'layers': []}
for batch in range(args.runs):
    for mode in (['native', 'layers'] if batch % 2 == 0 else ['layers', 'native']):
        before = subprocess.check_output(['ps', '-axo', 'pid,etime,comm'], text=True)
        environment = dict(os.environ, CHAT_CAPTION_LAYER_MEMORY=mode)
        with (args.output / f'{mode}-{batch}.log').open('w') as log:
            subprocess.run(['swift', 'test', '--package-path', str(lab), '--scratch-path', args.scratch_path, '-c', 'release', '--skip-build', '--filter', 'LayerCaptionBenchmarkTests.testRetainedMemory'], env=environment, stdout=log, stderr=subprocess.STDOUT, check=True)
        data = json.loads(Path(f'/tmp/chat-layer-caption-memory-{mode}.json').read_text())
        data['delta_bytes'] = data['after'] - data['before']
        data['other_build_processes_before'] = [line for line in before.splitlines() if any(name in line for name in ['swift-frontend', 'swift-build', 'xcodebuild', '/clang'])]
        (args.output / f'{mode}-{batch}.json').write_text(json.dumps(data, indent=2) + '\n')
        samples[mode].append(data)
        print(mode, batch, data['delta_bytes'], flush=True)
summary = {'samples': samples, 'median_delta_bytes': {mode: statistics.median(value['delta_bytes'] for value in values) for mode, values in samples.items()}}
(args.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(summary['median_delta_bytes'])
