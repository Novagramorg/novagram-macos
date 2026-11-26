import argparse
import collections
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True


def table(path):
    root = ET.parse(path)
    refs = {element.get('id'): element for element in root.iter() if element.get('id')}
    columns = [column.findtext('mnemonic') for column in root.findall('.//schema/col')]
    def value(element):
        element = refs.get(element.get('ref'), element)
        if element.tag == 'process':
            pid = element.find('pid')
            if pid is not None:
                return value(pid)
        return element.text
    return [dict(zip(columns, (value(element) for element in row))) for row in root.findall('.//row')]


def frame_key(row):
    return row.get('display'), row.get('swap-id'), row.get('surface-id')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lab', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    folder = Path(__file__).resolve().parent
    spec = importlib.util.spec_from_file_location('reporter', folder / 'report-all-widgets.py')
    reporter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reporter)
    args.out.mkdir(parents=True, exist_ok=True)
    records = []
    for fixture_index, name in enumerate(['order-book', 'clipped-ticker']):
        for renderer in (['lite', 'web'] if fixture_index % 2 == 0 else ['web', 'lite']):
            key = name + '-' + renderer
            trace = args.out / (key + '.trace')
            command = ['xcrun', 'xctrace', 'record', '--template', 'Animation Hitches', '--output', str(trace),
                       '--time-limit', '10s', '--target-stdout', str(args.out / (key + '.log')), '--launch', '--',
                       str(args.lab.resolve()), 'capture', str(folder / (name + '.html')), '--renderer', renderer,
                       '--seconds', '8', '--warmup', '2', '--width', '480', '--max-height', '6000', '--theme', 'dark',
                       '--visible', '--cpu', '--memory', '--logs', '--out', str(args.out / key)]
            print('Recording ' + key, flush=True)
            completed = subprocess.run(command, capture_output=True, text=True, timeout=120)
            (args.out / (key + '.xctrace.log')).write_text(completed.stdout + completed.stderr)
            if completed.returncode:
                raise SystemExit('Trace recording failed: ' + key)
            toc = args.out / (key + '.toc.xml')
            subprocess.run(['xcrun', 'xctrace', 'export', '--input', str(trace), '--toc', '--output', str(toc)],
                           check=True, capture_output=True, timeout=60)
            pid = ET.parse(toc).find('.//info/target/process').get('pid')
            tables = {}
            for schema in ['hitches-updates', 'hitches-frame-lifetimes', 'hitches-gpu', 'hitches']:
                path = args.out / (key + '.' + schema + '.xml')
                subprocess.run(['xcrun', 'xctrace', 'export', '--input', str(trace), '--xpath',
                                f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]', '--output', str(path)],
                               check=True, capture_output=True, timeout=60)
                tables[schema] = table(path)
            frames = {frame_key(row): row for row in tables['hitches-frame-lifetimes']}
            starts = {}
            commits = []
            for row in tables['hitches-updates']:
                if row['process'] != pid or not 3e9 <= int(row['start']) < 8e9:
                    continue
                key_frame = frame_key(row)
                starts[key_frame] = min(starts.get(key_frame, int(row['start'])), int(row['start']))
                commits.append(int(row['duration']) / 1e6)
            latency = []
            for key_frame, start in starts.items():
                if key_frame in frames:
                    frame = frames[key_frame]
                    latency.append((int(frame['start']) + int(frame['duration']) - start) / 1e6)
            gpu = [int(row['duration']) / 1e6 for row in tables['hitches-gpu'] if frame_key(row) in starts]
            record = dict(fixture=name, renderer=renderer, pid=int(pid), updates=reporter.summary(commits),
                          update_to_presentation=reporter.summary(latency),
                          associated_display_gpu=reporter.summary(gpu),
                          update_to_presentation_samples_ms=latency, associated_display_gpu_samples_ms=gpu,
                          recorded_hitches=tables['hitches'], command=command,
                          limitation='One instrumented run, trace seconds 3–8. CA update start to associated display-frame end; excludes work before CA update and physical scanout. GPU events cover the composed desktop frame, not solely the widget.')
            records.append(record)
            (args.out / 'results.json').write_text(json.dumps(records, indent=2) + '\n')
            print(json.dumps({k: v for k, v in record.items() if k in ['fixture', 'renderer', 'updates',
                                                                    'update_to_presentation', 'associated_display_gpu']}), flush=True)
    print('FINISHED', flush=True)


if __name__ == '__main__':
    main()
