import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import statistics
import subprocess
import tempfile


def distribution(values):
    return {'median': statistics.median(values), 'min': min(values), 'max': max(values)}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


parser = argparse.ArgumentParser()
parser.add_argument('--out', required=True, type=Path)
parser.add_argument('--rounds', type=int, default=3)
args = parser.parse_args()
if args.rounds < 1:
    parser.error('Use at least one round.')
repo = Path(__file__).resolve().parents[3]
package = repo / 'third-party/twidget'
output = args.out.resolve()
output.mkdir(parents=True, exist_ok=True)
test_source = package / 'Tests/TwidgetRendererTests/LocalPaintWorkloadTests.swift'
test_binary = package / '.build/release/twidgetPackageTests.xctest/Contents/MacOS/twidgetPackageTests'
source_hash = sha256(test_source)
binary_hash = sha256(test_binary)
modes = {
    'integer-width': 'integer-takeover-off-reuse-on.json',
    'fractional-width': 'fractional-takeover-off-reuse-on.json',
    'contained-integer-width': 'contained-integer-takeover-off-reuse-on.json',
}
count_keys = ['completed_states', 'layouts', 'document_jobs', 'document_installs', 'scroll_rasters', 'tile_jobs', 'compositor_rasters']
records = []
for run in range(args.rounds):
    for cache in ([False, True] if run % 2 == 0 else [True, False]):
        name = f'exclusion-cache-{int(cache)}-round-{run + 1}'
        directory = Path(tempfile.mkdtemp(prefix=name + '-', dir=output))
        environment = dict(os.environ)
        environment['TW_PAINT_EXCLUSION_CACHE'] = str(int(cache))
        environment['TW_LOCAL_PAINT_REUSE'] = '1'
        environment['TW_SCROLL_COMPOSITOR_TAKEOVER'] = '0'
        environment['TW_LOCAL_PAINT_WORKLOAD_REPORT'] = str(directory)
        if sha256(test_binary) != binary_hash or sha256(test_source) != source_hash:
            raise SystemExit('The test binary or workload source changed during the comparison.')
        try:
            result = subprocess.run([
                'swift', 'test', '--skip-build', '-c', 'release', '--package-path', str(package),
                '--filter', 'LocalPaintWorkloadTests',
            ], cwd=repo, env=environment, text=True, capture_output=True, timeout=360)
        except subprocess.TimeoutExpired as error:
            for stream in ['stdout', 'stderr']:
                content = getattr(error, stream) or b''
                if isinstance(content, bytes):
                    content = content.decode(errors='replace')
                (directory / f'{stream}.log').write_text(content)
            raise SystemExit(f'{name} timed out; inspect {directory}.')
        (directory / 'stdout.log').write_text(result.stdout)
        (directory / 'stderr.log').write_text(result.stderr)
        if result.returncode:
            raise SystemExit(f'{name} failed; inspect {directory}. Build the release renderer tests first.')
        if sha256(test_binary) != binary_hash or sha256(test_source) != source_hash:
            raise SystemExit('The test binary or workload source changed during the comparison.')
        for mode, filename in modes.items():
            path = directory / filename
            if not path.is_file():
                raise SystemExit(f'{name} did not write {filename}.')
            report = json.loads(path.read_text())
            steps = report['steps']
            if report['mode'] != mode or report['kind'] != 'renderer-component-fixed-work':
                raise SystemExit(f'{path} has an unexpected workload identity.')
            if report['completed_states'] != 60 or len(steps) != 60:
                raise SystemExit(f'{path} did not complete the expected 60 states.')
            if report['local_paint_reuse'] is not True or report['scroll_compositor_takeover'] is not False:
                raise SystemExit(f'{path} ran with unexpected optimization settings.')
            if [step['step'] for step in steps] != list(range(5, 65)):
                raise SystemExit(f'{path} did not report each expected mutation state once.')
            if any(step['render_queue_remaining'] != 0 for step in steps):
                raise SystemExit(f'{path} reported unfinished renderer work.')
            counts = {'completed_states': report['completed_states']}
            for key in count_keys[1:]:
                if any(type(step[key]) is not int or step[key] < 0 for step in steps):
                    raise SystemExit(f'{path} has invalid {key} counts.')
                counts[key] = sum(step[key] for step in steps)
            cache_samples = {
                'hits': sum(step['exclusion_cache_hits'] for step in steps),
                'misses': sum(step['exclusion_cache_misses'] for step in steps),
                'max_entries': max(step['exclusion_cache_entries'] for step in steps),
                'max_pointers': max(step['exclusion_cache_pointers'] for step in steps),
            }
            if bool(cache_samples['hits']) != cache:
                raise SystemExit(f'{path} did not exercise the requested cache setting.')
            if cache_samples['max_entries'] > 2 or cache_samples['max_pointers'] > 4096:
                raise SystemExit(f'{path} exceeded the exclusion cache limits.')
            cpu = report['cpu_ms'] / report['completed_states']
            elapsed = report['elapsed_ms'] / report['completed_states']
            if not all(math.isfinite(value) and value >= 0 for value in [cpu, elapsed]):
                raise SystemExit(f'{path} has invalid timing values.')
            if not math.isclose(cpu, report['cpu_ms_per_completed_state'], rel_tol=1e-9, abs_tol=1e-9):
                raise SystemExit(f'{path} has inconsistent CPU measurements.')
            record = {
                'run': run + 1, 'paint_exclusion_cache': cache, 'mode': mode,
                'report': str(path), 'path': report['path'], 'counts': counts,
                'cpu_ms_per_completed_state': cpu,
                'elapsed_ms_per_completed_state': elapsed,
                'cpu_ms': report['cpu_ms'], 'elapsed_ms': report['elapsed_ms'],
                'pixel_checks': report['pixel_checks'],
                'compositor_rasters': report['compositor_rasters'],
                'final_document_cache_samples': cache_samples,
            }
            records.append(record)
            (output / 'runs.json').write_text(json.dumps(records, indent=2) + '\n')
            print(f'{name} {mode}: {cpu:.3f} CPU ms/completed state; {counts}', flush=True)

summary = []
comparisons = []
for mode in modes:
    groups = {}
    for cache in [False, True]:
        group = [record for record in records if record['mode'] == mode and record['paint_exclusion_cache'] == cache]
        row = {'mode': mode, 'paint_exclusion_cache': cache, 'runs': len(group)}
        for key in ['cpu_ms_per_completed_state', 'elapsed_ms_per_completed_state', 'cpu_ms', 'elapsed_ms']:
            row[key] = distribution([record[key] for record in group])
        row['counts'] = {key: distribution([record['counts'][key] for record in group]) for key in count_keys}
        groups[cache] = row
        summary.append(row)
    mode_records = [record for record in records if record['mode'] == mode]
    equal_counts = {
        key: len({record['counts'][key] for record in mode_records}) == 1
        for key in count_keys
    }
    paired_counts = []
    for run in range(1, args.rounds + 1):
        pair = {record['paint_exclusion_cache']: record for record in mode_records if record['run'] == run}
        paired_counts.append({
            'run': run, 'equal_counts': pair[False]['counts'] == pair[True]['counts'],
            'cache_off': pair[False]['counts'], 'cache_on': pair[True]['counts'],
        })
    equal_work = all(equal_counts.values())
    before = groups[False]['cpu_ms_per_completed_state']['median']
    after = groups[True]['cpu_ms_per_completed_state']['median']
    reduction = 100 * (before - after) / before if equal_work and before > 0 else None
    comparisons.append({
        'mode': mode, 'equal_work': equal_work, 'equal_counts_across_all_runs': equal_counts,
        'paired_counts': paired_counts, 'cpu_ms_per_completed_state_reduction_percent': reduction,
    })
    for cache in [False, True]:
        cpu = groups[cache]['cpu_ms_per_completed_state']
        print(f"{mode} cache={int(cache)}: median {cpu['median']:.3f} CPU ms/completed state "
              f"(range {cpu['min']:.3f}–{cpu['max']:.3f})", flush=True)
    print(f'{mode}: equal work={equal_work}; CPU reduction={reduction}', flush=True)

equal_work = all(row['equal_work'] for row in comparisons)
report = {
    'method': 'Same release renderer test binary, 120 tracks and 60 completed mutation states per mode. '
              'Separate processes toggle only the paint exclusion cache; local paint reuse is enabled and '
              'scroll compositor takeover disabled. One state in flight; document and scroll tile completion '
              'checked. Applied state and installed-tree pixel checks run outside measured intervals. '
              'Process CPU includes worker threads. Elapsed time includes completion barriers. '
              'Work equality requires identical completed state, layout, document job, document install, '
              'scroll raster and tile job counts across all rounds of each mode. Renderer callbacks are '
              'not treated as completed frames. This is a renderer-component comparison, not WebKit, '
              'full-host throughput or display FPS.',
    'order': 'Cache off then on in round 1; reversed in alternate rounds',
    'test_source_sha256': source_hash,
    'test_binary_sha256': binary_hash,
    'equal_work': equal_work,
    'summary': summary,
    'comparisons': comparisons,
    'runs': records,
}
(output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
if not equal_work:
    raise SystemExit('Completed work counts differ; report.json records the mismatches and omits affected speedup claims.')
