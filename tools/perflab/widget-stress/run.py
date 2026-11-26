import argparse
import hashlib
import json
from pathlib import Path
import re
import statistics
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--lab', required=True, type=Path)
parser.add_argument('--out', required=True, type=Path)
parser.add_argument('--rounds', type=int, default=3)
parser.add_argument('--seconds', type=float, default=10)
parser.add_argument('--warmup', type=float, default=3)
parser.add_argument('--renderers', nargs='+', choices=['lite', 'web'], default=['lite', 'web'])
parser.add_argument('--fixtures', nargs='+')
parser.add_argument('--visible', action='store_true')
args = parser.parse_args()
if args.rounds < 1 or args.seconds <= args.warmup or args.warmup < 0:
    parser.error('Use positive rounds and seconds greater than the nonnegative warmup.')
args.out.mkdir(parents=True, exist_ok=True)
fixtures = sorted(Path(__file__).resolve().parent.glob('*.html'))
if args.fixtures:
    known = {fixture.stem for fixture in fixtures}
    if set(args.fixtures) - known:
        parser.error('Unknown fixtures: ' + ', '.join(sorted(set(args.fixtures) - known)))
    fixtures = [fixture for fixture in fixtures if fixture.stem in args.fixtures]
records = []
for run in range(args.rounds):
    for fixture in fixtures:
        for renderer in args.renderers if run % 2 == 0 else reversed(args.renderers):
            target = args.out / f'{fixture.stem}-{renderer}-{run + 1}'
            command = [str(args.lab.resolve()), 'capture', str(fixture), '--renderer', renderer,
                       '--out', str(target), '--width', '480', '--max-height', '6000', '--theme', 'dark',
                       '--seconds', str(args.seconds), '--warmup', str(args.warmup), '--cpu', '--memory', '--logs']
            if args.visible:
                command.append('--visible')
            print(f'{fixture.stem} {renderer} round {run + 1}', flush=True)
            result = subprocess.run(command, capture_output=True, text=True, timeout=args.seconds + 90)
            output = result.stdout + result.stderr
            (args.out / f'{target.name}.log').write_text(output)
            if result.returncode or 'log error:' in output or not re.search(r'rendered=true dead=- error=-', output):
                raise SystemExit(f'{target.name} failed; inspect its log')
            match = re.search(r'steady: own ([\d.]+)% helpers ([\d.]+)% total ([\d.]+)% windowserver ([\d.]+)% over ([\d.]+)s ops (\d+) fps ([\d.]+) cpu/frame ([\d.]+) ms', output)
            if not match:
                raise SystemExit(f'{target.name} has no CPU measurements')
            record = dict(zip(['own_cpu', 'helpers_cpu', 'total_cpu', 'windowserver_cpu', 'seconds', 'ops', 'host_fps', 'cpu_ms_per_host_frame'], map(float, match.groups())))
            record.update(fixture=fixture.stem, renderer=renderer, run=run + 1)
            records.append(record)
            (args.out / 'runs.json').write_text(json.dumps(records, indent=2) + '\n')
summary = []
for fixture in fixtures:
    for renderer in args.renderers:
        group = [r for r in records if r['fixture'] == fixture.stem and r['renderer'] == renderer]
        row = {'fixture': fixture.stem, 'renderer': renderer, 'runs': len(group)}
        for key in ['total_cpu', 'own_cpu', 'helpers_cpu', 'host_fps', 'cpu_ms_per_host_frame', 'ops']:
            row[key] = statistics.median(r[key] for r in group)
            row[key + '_range'] = [min(r[key] for r in group), max(r[key] for r in group)]
        summary.append(row)
        print(f"{fixture.stem:16s} {renderer:4s} CPU {row['total_cpu']:6.2f}% host callbacks {row['host_fps']:5.1f}/s")
(args.out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
(args.out / 'method.json').write_text(json.dumps({
    'comparison': 'Native and sandbox-backed WebKit with identical HTML and sandbox policy',
    'order': 'Renderer order reversed on alternate rounds',
    'visible': args.visible,
    'width_css': 480,
    'seconds': args.seconds,
    'warmup': args.warmup,
    'host_fps': 'Requested sandbox callbacks per second; not presented frames',
    'cpu': 'Percent of one core, host plus WebKit helpers, excluding WindowServer',
    'binary_sha256': hashlib.sha256(args.lab.read_bytes()).hexdigest(),
    'fixture_sha256': {fixture.name: hashlib.sha256(fixture.read_bytes()).hexdigest() for fixture in fixtures},
}, indent=2) + '\n')
