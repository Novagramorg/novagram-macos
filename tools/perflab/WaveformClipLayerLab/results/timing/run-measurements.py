from pathlib import Path
import json
import os
import re
import subprocess

root = Path('/tmp')
runs = [('forward', {'WAVEFORM_CLIP_BENCHMARK': '1'}, 'testConstructionProgressAndLayoutCosts'), ('reverse', {'WAVEFORM_CLIP_BENCHMARK': '1', 'WAVEFORM_CLIP_REVERSE': '1'}, 'testConstructionProgressAndLayoutCosts')]
for variant, suffix in [('original', '1'), ('current', '1'), ('current', '2'), ('original', '2')]:
    runs.append((f'{variant}-{suffix}', {'WAVEFORM_CLIP_MEMORY': variant}, 'testRetainedWaveformAllocationFootprint'))

def compiler_check(name, phase):
    result = subprocess.run(['ps', '-axo', 'pid,comm'], check=True, capture_output=True, text=True)
    active = '\n'.join(line for line in result.stdout.splitlines() if re.search(r'swift-frontend|xcodebuild|clang', line))
    (root / f'waveform-clip-{name}-{phase}.txt').write_text(active + ('\n' if active else ''))
    if active:
        raise RuntimeError(f'Competing compiler at {name} {phase}: {active}')

for name, values, test in runs:
    compiler_check(name, 'pre')
    environment = dict(os.environ, **values, WAVEFORM_CLIP_OUTPUT=str(root / f'waveform-clip-{name}.json'))
    command = ['caffeinate', '-i', 'swift', 'test', '--package-path', '/tmp/WaveformClipCorrected', '--scratch-path', '/tmp/WaveformClipCorrected-build', '-c', 'release', '--skip-build', '--filter', 'ClipLayerBenchmarkTests.' + test]
    with (root / f'waveform-clip-{name}.log').open('w') as log:
        result = subprocess.run(command, env=environment, stdout=log, stderr=subprocess.STDOUT)
    compiler_check(name, 'post')
    if result.returncode != 0:
        raise RuntimeError(f'{name} exited {result.returncode}')
    payload = json.loads((root / f'waveform-clip-{name}.json').read_text())
    print(name, 'complete', flush=True)
