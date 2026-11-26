import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--scratch-path', default='/tmp/ChatLayerEngineLab-release')
parser.add_argument('--output', type=Path, default=Path('/tmp/chat-layer-engine-memory'))
parser.add_argument('--runs', type=int, default=5)
args = parser.parse_args()
if args.runs < 1:
    parser.error('--runs must be positive')
args.output.mkdir(parents=True, exist_ok=True)
lab = Path(__file__).resolve().parent
samples = {'native': [], 'layers': []}
for batch in range(args.runs):
    for mode in (['native', 'layers'] if batch % 2 == 0 else ['layers', 'native']):
        result = args.output / f'{mode}-{batch}.json'
        environment = dict(os.environ, CHAT_LAYER_MEMORY_MODE=mode, CHAT_LAYER_MEMORY_RESULT=str(result.resolve()))
        with (args.output / f'{mode}-{batch}.log').open('w') as log:
            subprocess.run(['swift', 'test', '--package-path', str(lab), '--scratch-path', args.scratch_path, '-c', 'release', '--skip-build', '--filter', 'BenchmarkTests.testRetainedRowFootprint'], env=environment, stdout=log, stderr=subprocess.STDOUT, check=True)
        sample = json.loads(result.read_text())
        sample['delta'] = {key: sample['after'][key] - sample['before'][key] for key in sample['before']}
        samples[mode].append(sample)
        print(f'{mode} batch {batch}: {sample["delta"]}', flush=True)
summary = {'samples': samples, 'median_delta_bytes': {mode: {key: statistics.median(sample['delta'][key] for sample in values) for key in values[0]['delta']} for mode, values in samples.items()}}
(args.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
print(json.dumps(summary['median_delta_bytes'], indent=2))
