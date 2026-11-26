import argparse
import html
import json
import math
from pathlib import Path
import statistics


def summary(values):
    values = sorted(value for value in values if isinstance(value, (int, float)) and math.isfinite(value))
    if not values:
        return dict(count=0, mean=None, p95=None, maximum=None)
    return dict(count=len(values), mean=statistics.mean(values),
                p95=values[max(0, math.ceil(len(values) * 0.95) - 1)], maximum=max(values))


def timeline(path):
    if not path.exists():
        return None
    data = json.loads(path.read_text())
    records = data['records']
    result = {}
    for name, predicate in {
        'layout': lambda r: r.get('eventType') in ['layout', 'forced-layout'],
        'style': lambda r: r.get('eventType') == 'recalculate-styles',
        'paint': lambda r: r.get('eventType') == 'paint',
        'composite': lambda r: r.get('eventType') == 'composite',
        'frame_span': lambda r: r['type'] == 'timeline-record-type-rendering-frame',
    }.items():
        result[name] = summary([(r['endTime'] - r['startTime']) * 1000 for r in records if predicate(r)])
    frame_work = []
    for record in records:
        if record['type'] != 'timeline-record-type-rendering-frame':
            continue
        intervals = sorted((child['startTime'], child['endTime']) for child in record.get('children', [])
                           if isinstance(child.get('startTime'), (int, float))
                           and isinstance(child.get('endTime'), (int, float))
                           and child['endTime'] > child['startTime'])
        if not intervals:
            continue
        start, end = intervals[0]
        total = 0
        for next_start, next_end in intervals[1:]:
            if next_start <= end:
                end = max(end, next_end)
            else:
                total += end - start
                start, end = next_start, next_end
        frame_work.append((total + end - start) * 1000)
    result['frame_work'] = summary(frame_work)
    result['record_count'] = len(records)
    result['start'] = data.get('startTime')
    result['end'] = data.get('endTime')
    return result


def focused_report(animation, presentation, output):
    def num(value):
        return f'{value:.2f}' if isinstance(value, (int, float)) else '—'

    def median(records, getter):
        values = [getter(record) for record in records]
        values = [value for value in values if isinstance(value, (int, float))]
        return statistics.median(values) if values else None

    def table(headings, rows):
        return '<div class="scroll"><table><thead><tr>' + ''.join(
            '<th>' + html.escape(value) + '</th>' for value in headings
        ) + '</tr></thead><tbody>' + ''.join(
            '<tr>' + ''.join('<td>' + html.escape(str(value)) + '</td>' for value in row) + '</tr>'
            for row in rows
        ) + '</tbody></table></div>'

    document = ''
    if animation:
        runs = json.loads((animation / 'runs.json').read_text())
        method = json.loads((animation / 'method.json').read_text())
        (output / 'animation.json').write_text(json.dumps(dict(method=method, runs=runs), indent=2) + '\n')
        rows = []
        for name in dict.fromkeys(record['fixture'] for record in runs):
            native = [record for record in runs if record['fixture'] == name and record['renderer'] == 'lite']
            web = [record for record in runs if record['fixture'] == name and record['renderer'] == 'web']
            native_peak = max((record['native_pipeline']['maximum'] or 0 for record in native), default=0)
            web_peak = max((record['webkit_timeline']['frame_work']['maximum'] or 0 for record in web), default=0)
            rows.append([name, str(sum(record['pass'] for record in native + web)) + '/' + str(len(native + web)),
                         num(median(native, lambda r: r['native_pipeline']['mean'])),
                         num(median(native, lambda r: r['native_pipeline']['p95'])), num(native_peak or None),
                         num(median(web, lambda r: r['webkit_timeline']['frame_work']['mean'])),
                         num(median(web, lambda r: r['webkit_timeline']['frame_work']['p95'])), num(web_peak or None),
                         num(median(native, lambda r: r['host_callbacks_per_second'])) + ' / ' + num(median(web, lambda r: r['host_callbacks_per_second'])),
                         num(median(native, lambda r: r['cpu_ms_per_callback'] if r['host_callbacks_per_second'] else None)) + ' / ' + num(median(web, lambda r: r['cpu_ms_per_callback'] if r['host_callbacks_per_second'] else None)),
                         num(median(native, lambda r: r['gpu_ms_per_second'])) + ' / ' + num(median(web, lambda r: r['gpu_ms_per_second'])),
                         num(median(native, lambda r: r['canvas_gpu_ms_per_buffer'] if r.get('canvas_gpu_buffers') else None))])
        document += '<h2>Repeated animation measurements</h2><p>Six stress widgets, three runs per renderer; 8 seconds per run with a 2-second warmup. WebKit Inspector records a separate 5-second interval. Mean and p95 columns are medians of the three per-run statistics; worst is the largest observed sample across all three runs. Times are milliseconds unless stated otherwise. Native pipeline passes and WebKit recorded frame work have different scopes, so these columns do not support a renderer speedup ratio.</p>'
        document += table(['Widget', 'Successful runs', 'Native pipeline mean', 'Native pipeline p95', 'Native pipeline worst',
                           'WebKit frame work mean', 'WebKit frame work p95', 'WebKit frame work worst',
                           'Host callbacks/s N / W', 'CPU work/callback N / W · ms', 'GPU work N / W · ms/s',
                           'Native canvas GPU · ms/buffer'], rows)
        document += '<p>Canvas and compositor-only paths can animate without native layout passes. A missing pipeline value is not zero frame cost. Orbit-wall uses CSS animation and has zero host callbacks; that is not zero display FPS. Native pipeline diagnostics are rounded to 0.01 ms. GPU counters exclude WindowServer and may report zero while composition continues. <a href="animation.json">All 36 runs and samples</a>.</p>'
    if presentation:
        runs = json.loads((presentation / 'results.json').read_text())
        (output / 'presentation.json').write_text(json.dumps(runs, indent=2) + '\n')
        rows = []
        for record in runs:
            timing = record['update_to_presentation']
            gpu = record['associated_display_gpu']
            rows.append([record['fixture'], 'Native' if record['renderer'] == 'lite' else 'WebKit',
                         timing['count'], num(timing['mean']), num(timing['p95']), num(timing['maximum']),
                         num(record['updates']['mean']), num(record['updates']['p95']), num(gpu['mean']), num(gpu['p95'])])
        document += '<h2>Instrumented presentation timing</h2><p>One Animation Hitches trace per renderer for two stress widgets; trace seconds 3–8. Latency starts at the host Core Animation update and ends at the associated display-frame lifetime end. It includes presentation waiting but excludes JavaScript and renderer preparation before that update, and physical scanout. These are host-process update samples, not a display FPS count. WebKit content-process commits are not included in this host-only selection, so it does not establish matched widget-frame latency. Four traces are not a repeated statistical comparison.</p>'
        document += table(['Widget', 'Renderer', 'Associated samples', 'Update→presentation mean · ms',
                           'Update→presentation p95 · ms', 'Update→presentation worst · ms', 'CA update mean · ms',
                           'CA update p95 · ms', 'Associated desktop GPU mean · ms', 'Associated desktop GPU p95 · ms'], rows)
        document += '<p class="note">Associated GPU durations belong to the whole composed desktop frame, not solely the widget. They must not be interpreted as isolated widget GPU cost. <a href="presentation.json">Raw samples and trace commands</a>. <a href="https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app">Apple’s frame-lifetime definitions</a>.</p>'
    return document


def overview(rows, animation, presentation):
    def number(value):
        return f'{value:.2f}' if value is not None else '—'

    def table(headings, values):
        return '<div class="scroll compact"><table><thead><tr>' + ''.join(
            '<th>' + html.escape(value) + '</th>' for value in headings
        ) + '</tr></thead><tbody>' + ''.join(
            '<tr>' + ''.join('<td>' + html.escape(str(value)) + '</td>' for value in row) + '</tr>'
            for row in values
        ) + '</tbody></table></div>'

    paired = [row for row in rows if row['native'].get('pass') and row['webkit'].get('pass')]
    document = '<section class="overview"><h2>Overall conclusion</h2>'
    document += '<p><strong>We cannot yet claim smoother animation than WebKit.</strong> The timings below cover different parts of rendering. The clearest latency concern is the clipped ticker; order book and reflow cards also use more CPU per animation callback.</p>' if animation and presentation else '<p>Startup and layout screening is complete for the pairs listed below. Full animation latency needs matched frame measurements.</p>'
    if paired:
        startup = [statistics.median(row[engine]['first_content_ms'] for row in paired) for engine in ['native', 'webkit']]
        memory = [statistics.median(row[engine]['footprint_mb'] for row in paired) for engine in ['native', 'webkit']]
        document += f'<p>Across {len(paired)} widgets, median first-content time was <strong>{startup[0]:.1f} vs {startup[1]:.1f} ms</strong> and memory was <strong>{memory[0]:.1f} vs {memory[1]:.1f} MB</strong> (native / WebKit).</p>'
    animation_runs = json.loads((animation / 'runs.json').read_text()) if animation else []
    presentation_runs = json.loads((presentation / 'results.json').read_text()) if presentation else []
    if animation_runs or presentation_runs:
        document += '<h3>Where native looks slower</h3><ul>'
        ticker = {r['renderer']: r for r in presentation_runs if r['fixture'] == 'clipped-ticker'}
        if len(ticker) == 2:
            native, web = [ticker[engine]['update_to_presentation']['p95'] for engine in ['lite', 'web']]
            document += f'<li><strong>Clipped ticker:</strong> host update-to-presentation p95 was <strong>{native:.2f} vs {web:.2f} ms</strong> — native was {native - web:.2f} ms higher in this trace. This is a host-stage warning, not a confirmed full-widget frame regression.</li>'
        for name in ['order-book', 'reflow-cards']:
            values = [statistics.median(r['cpu_ms_per_callback'] for r in animation_runs if r['fixture'] == name and r['renderer'] == engine) for engine in ['lite', 'web']]
            document += f'<li><strong>{html.escape(name.replace("-", " ").capitalize())}:</strong> CPU work per animation callback was <strong>{values[0]:.2f} vs {values[1]:.2f} ms</strong> ({(values[0] / values[1] - 1) * 100:.0f}% more for native). This measures CPU cost, not displayed-frame latency.</li>'
        document += '</ul>'
    document += '</section>'
    if animation_runs:
        compact_rows = []
        for name in dict.fromkeys(r['fixture'] for r in animation_runs):
            cells = [name.replace('-', ' ').capitalize()]
            for engine in ['lite', 'web']:
                records = [r for r in animation_runs if r['fixture'] == name and r['renderer'] == engine]
                timings = [r['native_pipeline'] if engine == 'lite' else r['webkit_timeline']['frame_work'] for r in records]
                values = [[t[key] for t in timings if t[key] is not None] for key in ['mean', 'p95']]
                cells.append(' / '.join(number(statistics.median(v) if v else None) for v in values))
            compact_rows.append(cells)
        document += '<h2>Animation work timings</h2><p><strong>Mean / p95 in milliseconds; lower is less recorded work.</strong> These are different timers: native renderer passes versus WebKit recorded frame work. Do not use their ratio as a speedup. p95 is the value at or below which 95% of samples fall; entries are medians across three runs.</p>'
        document += table(['Widget', 'Native pipeline · mean / p95', 'WebKit frame work · mean / p95'], compact_rows)
        document += '<p class="small">— means the native canvas or compositor path had no measured pipeline passes. It does not mean zero cost. Neither column includes the entire GPU-to-display path.</p>'
    if presentation_runs:
        compact_rows = []
        for name in dict.fromkeys(r['fixture'] for r in presentation_runs):
            cells = [name.replace('-', ' ').capitalize()]
            for engine in ['lite', 'web']:
                timing = next(r['update_to_presentation'] for r in presentation_runs if r['fixture'] == name and r['renderer'] == engine)
                cells.append(number(timing['mean']) + ' / ' + number(timing['p95']))
            compact_rows.append(cells)
        document += '<h2>Host update-to-presentation timings</h2><p>Mean / p95 in milliseconds, one trace per renderer. These include presentation waiting, but exclude earlier JavaScript work and WebKit content-process commits. They are not matched end-to-end widget frames.</p>'
        document += table(['Widget', 'Native · mean / p95', 'WebKit · mean / p95'], compact_rows)
    document += '<p class="small">Coverage: 249 widgets opened in both renderers; 36 repeated animation runs; 4 presentation traces. Four fixtures have unmatched 3D activity and ten have document-height differences. Details and evidence are below.</p>'
    return document


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--animation', type=Path)
    parser.add_argument('--presentation', type=Path)
    args = parser.parse_args()
    method = json.loads((args.input / 'method.json').read_text())
    if method['rounds'] != 1:
        raise SystemExit('This report expects one screening round; retain repeated runs for separate statistical analysis.')
    runs = [json.loads(line) for line in (args.input / 'runs.jsonl').read_text().splitlines()]
    groups = {}
    for record in runs:
        groups.setdefault(record['fixture'], {})[record['renderer']] = record
    rows = []
    for fixture in method['fixtures']:
        pair = groups.get(fixture['name'], {})
        if not pair:
            continue
        native, web = pair.get('lite', {}), pair.get('web', {})
        profile = timeline(args.input / (web.get('key', 'missing') + '.timeline.json'))
        count = native.get('steady_layout_count', 0)
        row = dict(fixture=fixture['name'], native=native, webkit=web, webkit_timeline=profile,
                   native_steady_layout_mean_ms=native.get('steady_pure_layout_total_ms', 0) / count if count else None,
                   native_steady_pipeline_mean_ms=native.get('steady_pipeline_total_ms', 0) / count if count else None,
                   height_delta=native['height'] - web['height'] if 'height' in native and 'height' in web else None)
        row['unmatched_3d_activity'] = bool(native and web and
            ((native.get('surface_fps', 0) > 0) != (web.get('surface_fps', 0) > 0)))
        for label, record in [('native', native), ('webkit', web)]:
            shots = list((args.input / record.get('key', 'missing')).glob('*.png'))
            row[label + '_snapshot'] = str(shots[0]) if shots else None
        rows.append(row)
    counts = dict(widgets=len(method['fixtures']), completed_pairs=sum(bool(r['native']) and bool(r['webkit']) for r in rows),
                  native_pass=sum(bool(r['native'].get('pass')) for r in rows),
                  webkit_pass=sum(bool(r['webkit'].get('pass')) for r in rows),
                  webkit_timelines=sum(r['webkit_timeline'] is not None for r in rows),
                  unmatched_3d_activity=sum(r['unmatched_3d_activity'] for r in rows),
                  height_differences_over_1pt=sum(r['height_delta'] is not None and abs(r['height_delta']) > 1 for r in rows))
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / 'comparison.json').write_text(json.dumps(dict(method=method, counts=counts, rows=rows), indent=2) + '\n')
    def num(value, digits=2):
        return f'{value:.{digits}f}' if isinstance(value, (float, int)) else '—'
    def link(path, label):
        return f'<a href="{html.escape(path, quote=True)}">{html.escape(label)}</a>' if path else '—'
    def status(record):
        return 'PASS' if record.get('pass') else ('FAIL' if record else 'PENDING')
    def cpu(record):
        value = record.get('cpu_percent')
        return num(value * 10, 1) if isinstance(value, (int, float)) else '—'
    def pair(a, b, digits=2):
        return num(a, digits) + ' / ' + num(b, digits)
    table_rows = []
    for index, row in enumerate(rows, 1):
        n, w, t = row['native'], row['webkit'], row['webkit_timeline']
        t = t or {}
        failed = not n.get('pass') or not w.get('pass')
        review = row['unmatched_3d_activity'] or (row['height_delta'] is not None and abs(row['height_delta']) > 1)
        notes = []
        if row['height_delta'] is not None and abs(row['height_delta']) > 1:
            notes.append(f'Height differs by {row["height_delta"]:+.0f} CSS px (native minus WebKit); review snapshots and animation state.')
        if row['unmatched_3d_activity']:
            notes.append('3D comparison unavailable: only one renderer reported active shared-backend frames. Smoke PASS does not establish equivalent rendered work.')
        for label, record in [('N', n), ('W', w)]:
            notes += [label + ': ' + str(error) for error in record.get('errors', [])]
            if record.get('dead'): notes.append(label + ': stopped ' + record['dead'])
            if record.get('error'): notes.append(label + ': ' + record['error'])
            if record and record.get('returncode') != 0: notes.append(label + ': exit ' + str(record['returncode']))
            notes += [label + ': ' + warning for warning in record.get('warnings', [])]
            if label == 'N':
                notes += record.get('pressure', [])
        diagnostics = '<details><summary>Logs & snapshots</summary>'
        for label, record in [('Native', n), ('WebKit', w)]:
            diagnostics += link(str(args.input / (record.get('key', 'missing') + '.log')), label + ' log') + ' · '
        diagnostics += link(row['native_snapshot'], 'Native PNG') + ' · ' + link(row['webkit_snapshot'], 'WebKit PNG')
        diagnostics += '<p>' + html.escape('; '.join(notes) or 'No reported errors or warnings.') + '</p></details>'
        columns = [str(index), html.escape(row['fixture']), status(n) + ' / ' + status(w) + (' · REVIEW' if review else ''),
                   pair(n.get('first_content_ms'), w.get('first_content_ms'), 1),
                   pair(row['native_steady_layout_mean_ms'], t.get('layout', {}).get('mean'), 3),
                   (str(int(n['steady_layout_count'])) if 'steady_layout_count' in n else '—') + ' / ' + str(t.get('layout', {}).get('count', '—')),
                   num(row['native_steady_pipeline_mean_ms'], 3),
                   num(t.get('frame_work', {}).get('mean'), 3) + ' / ' + num(t.get('frame_work', {}).get('p95'), 3),
                   str(t.get('frame_work', {}).get('count', '—')),
                   num(t.get('paint', {}).get('mean'), 3),
                   pair(n.get('host_callbacks_per_second'), w.get('host_callbacks_per_second'), 1),
                   cpu(n) + ' / ' + cpu(w),
                   pair(n.get('gpu_ms_per_second'), w.get('gpu_ms_per_second'), 1),
                   pair(n.get('footprint_mb'), w.get('footprint_mb'), 1),
                   pair(n.get('height'), w.get('height'), 0),
                   pair(n.get('surface_gpu_ms_per_frame') if n.get('surface_fps', 0) > 0 else None,
                        w.get('surface_gpu_ms_per_frame') if w.get('surface_fps', 0) > 0 else None, 3),
                   num(n.get('canvas_gpu_ms_per_buffer'), 3) if n.get('canvas_gpu_buffers', 0) else '—', diagnostics]
        table_rows.append('<tr data-failed="' + str(failed).lower() + '">' + ''.join('<td' + (' class="extra"' if i not in [1, 2, 3, 4, 6, 7, 13, 17] else '') + '>' + c + '</td>' for i, c in enumerate(columns)) + '</tr>')
    headings = ['#', 'Widget', 'Status N / W', 'First content N / W · ms', 'Steady layout mean N / W · ms',
                'Layout samples N / W', 'Native pipeline mean · ms', 'WebKit recorded frame work mean / p95 · ms', 'WebKit frame samples',
                'WebKit paint mean · ms', 'Host callbacks/s N / W', 'CPU work N / W · ms/s', 'GPU work N / W · ms/s',
                'Footprint N / W · MB', 'Height N / W · CSS px', 'Shared 3D GPU N / W · ms/frame',
                'Native canvas GPU · ms/buffer', 'Evidence']
    document = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>All Widgets — Native vs WebKit</title><style>
:root{font-family:system-ui,sans-serif;color:#17232e;background:#f3f6f8;font-size:14px}body{margin:32px}h1{font-size:30px;margin-bottom:6px}p{max-width:1150px;line-height:1.6}a{color:#087caa}strong{font-weight:650}.cards{display:flex;gap:12px;flex-wrap:wrap;margin:24px 0}.card{background:white;border:1px solid #d9e2e8;border-radius:10px;padding:16px;min-width:130px}.card b{font-size:26px;display:block}.controls{display:flex;gap:18px;align-items:center;margin:20px 0}input[type=search]{padding:10px;width:430px;border:1px solid #bdcbd4;border-radius:6px}.scroll{overflow:auto;max-height:72vh;border:1px solid #ccd8df;background:white}table{border-collapse:separate;border-spacing:0;font-variant-numeric:tabular-nums;width:100%}th{position:sticky;top:0;background:#17394b;color:white;text-align:left;z-index:2;min-width:110px}td,th{padding:10px;border-bottom:1px solid #dce4e9;vertical-align:top}#catalog th:nth-child(2),#catalog td:nth-child(2){min-width:300px;max-width:390px;overflow-wrap:anywhere}tr:nth-child(even){background:#f3f7fa}tr[data-failed=true]{background:#fff1ed}summary{cursor:pointer;white-space:nowrap}details p{min-width:280px}li{margin:8px 0;line-height:1.5}.note{border-left:4px solid #db9b23;background:#fff8e8;padding:12px 16px}.small{color:#536673;font-size:12px}
</style><h1>All Widgets — Native vs WebKit</h1><p>15 October 2026 · Apple M5 Pro · 48 GB · macOS 26.4 · release build · N = native, W = sandbox-backed WKWebView</p>'''
    document += '<style>.overview{background:white;border:1px solid #ccd8df;border-radius:12px;padding:8px 24px 18px;max-width:1100px}.overview h2{margin-bottom:8px}.compact{max-width:1150px;max-height:none}.compact th{position:static}#catalog .extra{display:none}body.full-metrics #catalog .extra{display:table-cell}details>summary{white-space:normal;padding:12px 0}h2{margin-top:28px}.controls{flex-wrap:wrap}</style>'
    document += overview(rows, args.animation, args.presentation)
    document += '<details><summary><strong>Detailed measurements, method, and review flags</strong></summary>'
    document += '<div class="cards">' + ''.join(f'<div class="card"><b>{value}</b>{label}</div>' for label, value in [
        ('widgets in catalog', counts['widgets']), ('pairs completed', counts['completed_pairs']),
        ('native smoke passes', counts['native_pass']), ('WebKit smoke passes', counts['webkit_pass']),
        ('WebKit timelines', counts['webkit_timelines'])]) + '</div>'
    if counts['unmatched_3d_activity']:
        document += f'<p class="note"><strong>{counts["unmatched_3d_activity"]} fixtures have unmatched 3D activity.</strong> One renderer reports active shared-backend frames while the other reports none. Their 3D performance is not comparable in this run; missing GPU samples are shown as —. Snapshots may omit externally composed Metal surfaces. Smoke passes do not resolve this coverage gap.</p>'
    different_heights = [row for row in rows if row['height_delta'] is not None and abs(row['height_delta']) > 1]
    if different_heights:
        document += '<details open><summary><strong>' + str(len(different_heights)) + ' fixtures differ in document height by more than 1 CSS px</strong></summary><p>These need visual review; animation state and layout differences can both affect height. Values below are native / WebKit.</p><ul>'
        for row in sorted(different_heights, key=lambda row: -abs(row['height_delta'])):
            document += '<li>' + html.escape(row['fixture']) + ': ' + pair(row['native']['height'], row['webkit']['height'], 0) + ' px</li>'
        document += '</ul></details>'
    document += '''<p class="note"><strong>These are screening measurements, not an end-to-end FPS ranking.</strong> WebKit recorded frame work is the union of timed child events within each Inspector rendering frame. Raw frame spans can contain idle gaps, so they are retained in JSON but not presented as work time. Recorded work excludes uninstrumented work and the full GPU/display pipeline. Native pipeline time has a different scope and must not be divided by WebKit frame work to claim a speedup. Missing values are shown as —, never as zero.</p>
<details open><summary><strong>Method and interpretation</strong></summary><ul>
<li>Every HTML file from the app’s shared All Widgets catalog is opened once in each renderer, serially, at 480 CSS px wide, dark theme, maximum document height 6000 px, with an opaque 900-point host window. This is startup/autonomous-animation coverage, not click-through interaction or full off-screen visual validation.</li>
<li>The baseline capture runs for 3 seconds with the first second excluded from CPU/GPU and native steady-layout counters. Counter collection reduces the actual sampled interval slightly; raw logs preserve it. Renderer order alternates between widgets.</li>
<li>WebKit’s Inspector connects <em>after</em> the baseline measurements and snapshot, then records a separate 2-second interval. Its overhead and the later animation phase prevent strict equal-work latency ratios. Layout includes normal and forced-layout events. Native pure-layout time includes layout and scroll-offset restoration; native pipeline time additionally includes document preparation and layer work.</li>
<li>Zero layout samples means no layout work in that interval; the mean is —. CSS animations can continue in Core Animation with zero host callbacks. Callback rate is not display FPS.</li>
<li>CPU work sums host and its WebKit helpers. GPU work is the delta of accumulated AGX counters, in milliseconds per second, not per-frame latency. Zero reported GPU work does not imply zero compositor work. WindowServer is excluded because its counters cover the whole desktop.</li>
<li>Shared 3D GPU values come from Metal command-buffer timing in the same native 3D backend used by both renderers. Native canvas GPU timing covers only its accelerated buffers. Neither includes all composition or scanout.</li>
<li>First content is the host diagnostic signal, not a measured first displayed pixel. PASS requires successful process exit, rendered content, a saved snapshot, timing output, no stopped sandbox, and no reported script error. It does not establish semantic or pixel equivalence. Heights and screenshots can differ with animation state.</li>
<li>This is one short run per widget. Use longer repeated runs and deterministic interactions before treating small differences as performance regressions.</li>
</ul></details>'''
    document += '<p><a href="comparison.json">Full structured measurements and hashes</a>. Layout/frame definitions follow <a href="https://webkit.org/web-inspector/timelines-tab/">WebKit’s Timelines documentation</a>. <a href="renderer-tests.log">Renderer regression suite</a>: 537 tests, 4 skipped, zero failures. <a href="sandbox-tests.log">Sandbox tests</a> could not compile because HostOpsAttackTests attempts four assignments to the constant hidesHostFunctions.</p>'
    document += '<h2>Catalog overview</h2><p>Medians across completed widget pairs in each family. First content is the host signal; footprint is the host plus its WebKit helpers. These summarize startup and memory, separately from the animation timings below.</p><table><thead><tr><th>Family</th><th>Completed pairs</th><th>First content N / W · ms</th><th>Footprint N / W · MB</th></tr></thead><tbody>'
    for family in dict.fromkeys(row['fixture'].split('/')[0] for row in rows):
        completed = [row for row in rows if row['fixture'].split('/')[0] == family and row['native'] and row['webkit']]
        def family_median(renderer, metric):
            values = [row[renderer].get(metric) for row in completed]
            values = [value for value in values if isinstance(value, (int, float))]
            return statistics.median(values) if values else None
        document += '<tr><td>' + html.escape(family) + '</td><td>' + str(len(completed)) + '</td><td>' + pair(
            family_median('native', 'first_content_ms'), family_median('webkit', 'first_content_ms'), 1
        ) + '</td><td>' + pair(family_median('native', 'footprint_mb'), family_median('webkit', 'footprint_mb'), 1) + '</td></tr>'
    document += '</tbody></table>'
    document += focused_report(args.animation, args.presentation, args.out)
    document += '</details><h2>All 249 widgets</h2><p>N = native; W = WebKit. Expand all metrics for GPU counters, sample counts, and additional diagnostics.</p><div class="controls"><input type="search" id="query" placeholder="Filter by widget path"><label><input type="checkbox" id="failures"> Failures only</label><label><input type="checkbox" id="metrics"> Show all metrics</label><span id="shown"></span></div><div class="scroll"><table id="catalog"><thead><tr>'
    document += ''.join('<th' + (' class="extra"' if i not in [1, 2, 3, 4, 6, 7, 13, 17] else '') + '>' + html.escape(h) + '</th>' for i, h in enumerate(headings)) + '</tr></thead><tbody>' + ''.join(table_rows) + '</tbody></table></div>'
    document += '<script>document.querySelector("#metrics").addEventListener("change",event=>document.body.classList.toggle("full-metrics",event.target.checked));</script>'
    document += '''<script>const q=document.querySelector('#query'),f=document.querySelector('#failures'),rows=[...document.querySelectorAll('#catalog tbody tr')];function filter(){let n=0;for(const r of rows){r.hidden=!r.cells[1].textContent.toLowerCase().includes(q.value.toLowerCase())||(f.checked&&r.dataset.failed!=='true');if(!r.hidden)n++}document.querySelector('#shown').textContent=n+' rows shown'}q.addEventListener('input',filter);f.addEventListener('change',filter);filter();</script></html>'''
    (args.out / 'comparison.html').write_text(document)
    print(json.dumps(counts, indent=2))


if __name__ == '__main__':
    main()
