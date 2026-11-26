import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--out', required=True, type=Path)
parser.add_argument('--rounds', type=int, default=3)
args = parser.parse_args()
if args.rounds < 1:
    parser.error('Use at least one round.')
repo = Path(__file__).resolve().parents[3]
package = repo / 'third-party/twidget'
args.out.mkdir(parents=True, exist_ok=True)
records = []
for run in range(args.rounds):
    for reuse in ([False, True] if run % 2 == 0 else [True, False]):
        name = f'contained-reuse-{int(reuse)}-{run + 1}'
        environment = dict(os.environ)
        environment['TW_LOCAL_PAINT_REUSE'] = str(int(reuse))
        environment['TW_SCROLL_COMPOSITOR_TAKEOVER'] = '0'
        report_directory = args.out.resolve() / name
        report_path = report_directory / f'contained-integer-takeover-off-reuse-{"on" if reuse else "off"}.json'
        report_path.unlink(missing_ok=True)
        environment['TW_LOCAL_PAINT_WORKLOAD_REPORT'] = str(report_directory)
        result = subprocess.run([
            'swift', 'test', '--package-path', str(package), '-c', 'release', '--skip-build',
            '--filter', 'LocalPaintWorkloadTests/testContainedIntegerWidthFixedWorkAndInstalledPixels',
        ], env=environment, text=True, capture_output=True, timeout=120)
        log = result.stdout + result.stderr
        (args.out / f'{name}.log').write_text(log)
        if result.returncode:
            raise SystemExit(f'{name} failed; inspect its log. Build the release renderer tests first.')
        if not report_path.is_file():
            raise SystemExit(f'{name} did not write its workload report.')
        report = json.loads(report_path.read_text())
        if report['completed_states'] != 60:
            raise SystemExit(f'{name} did not complete the expected workload.')
        if report['local_paint_reuse'] != reuse or report['scroll_compositor_takeover']:
            raise SystemExit(f'{name} ran with unexpected optimization settings.')
        report['run'] = run + 1
        elapsed = sorted(step['elapsed_ms'] for step in report['steps'])
        report['elapsed_p95_ms'] = elapsed[math.ceil(len(elapsed) * .95) - 1]
        records.append(report)
        (args.out / 'runs.json').write_text(json.dumps(records, indent=2) + '\n')
        print(f"{name}: {report['cpu_ms_per_completed_state']:.3f} CPU ms/completed state, "
              f"{report['compositor_rasters']} rasters", flush=True)
summary = []
for reuse in [False, True]:
    group = [record for record in records if record['local_paint_reuse'] == reuse]
    row = {'local_paint_reuse': reuse, 'runs': len(group)}
    for key in ['cpu_ms_per_completed_state', 'elapsed_ms', 'elapsed_p95_ms', 'compositor_rasters']:
        values = [record[key] for record in group]
        row[key] = {'median': statistics.median(values), 'min': min(values), 'max': max(values)}
    summary.append(row)
test_source = package / 'Tests/TwidgetRendererTests/LocalPaintWorkloadTests.swift'
test_binary = package / '.build/release/twidgetPackageTests.xctest/Contents/MacOS/twidgetPackageTests'
report = {
    'method': 'Same release renderer test binary, 120 contained tracks and 60 completed mutation states. '
              'One state in flight; document and scroll tile completion checked. Applied state and fresh '
              'installed-tree pixel checks run outside measured intervals. Process CPU includes worker threads. '
              'Elapsed time includes renderer queue draining and test completion barriers. '
              'This is a renderer-component comparison, not WebKit, full-host throughput or display FPS.',
    'order': 'Reuse setting reversed in alternate rounds',
    'test_source_sha256': hashlib.sha256(test_source.read_bytes()).hexdigest(),
    'test_binary_sha256': hashlib.sha256(test_binary.read_bytes()).hexdigest() if test_binary.is_file() else None,
    'summary': summary,
    'runs': records,
}
(args.out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
