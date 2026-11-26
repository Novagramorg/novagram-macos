import json, sys, statistics
rep = json.load(open(sys.argv[1]))
rows = [json.loads(l) for l in open(sys.argv[2])]
def window(a, b):
    sel = [r for r in rows if a <= r['t'] <= b]
    if len(sel) < 2:
        return None, None
    ws = (sel[-1]['ws'] - sel[0]['ws']) / (sel[-1]['t'] - sel[0]['t'])
    gpu = sum(r['gpu'] for r in sel) / len(sel)
    return ws, gpu
cols = ['frames', 'hitches', 'hitchesOver33ms', 'hitchTimePercent', 'worstGapMs', 'cpuCores', 'mainThreadBusyPercent', 'scrolledRange', 'avg_visibleEmoji', 'avg_visiblePlaceholders', 'visibleEmoji', 'visiblePlaceholders', 'settleSeconds', 'placeholdersAfterSettle', 'blankPercent', 'maxBlank', 'merges', 'worstMergeMs', 'locationChanges', 'jumpCells', 'distinctMessages', 'avg_atBottom', 'settleMedianMs', 'settleMaxMs', 'violations']
short = {'hitchesOver33ms': 'h33', 'hitchTimePercent': 'hitch%', 'worstGapMs': 'worst', 'mainThreadBusyPercent': 'main%', 'scrolledRange': 'range', 'avg_visibleEmoji': 'vis', 'avg_visiblePlaceholders': 'ph', 'visibleEmoji': 'vis', 'visiblePlaceholders': 'ph', 'settleSeconds': 'settle', 'placeholdersAfterSettle': 'phLeft', 'cpuCores': 'cpu', 'blankPercent': 'blank%', 'worstMergeMs': 'worstMerge', 'locationChanges': 'locs', 'jumpCells': 'jumps', 'distinctMessages': 'seen', 'avg_atBottom': 'atEnd%'}
print("label", rep['label'], rep.get('arguments', {}).get('-PerfLabPlaceholder', 'shimmer'))
agg = {}
for e in rep['entries']:
    m = e['metrics']
    ws, gpu = window(m.get('startUnixTime', 0), m.get('endUnixTime', 0))
    parts = [f"{e['scenario']:<12}{e['run']}"]
    for c in cols:
        if c in m:
            parts.append(f"{short.get(c, c)}={m[c]:g}")
    if ws is not None:
        parts.append(f"wsCores={ws:.2f} gpu%={gpu:.0f}")
        m['wsCores'] = ws; m['gpu'] = gpu
    print(' '.join(parts))
    agg.setdefault(e['scenario'], []).append(m)
print("-- medians")
for sc, ms in agg.items():
    keys = ['hitches', 'hitchesOver33ms', 'hitchTimePercent', 'cpuCores', 'mainThreadBusyPercent', 'wsCores', 'gpu', 'avg_visiblePlaceholders', 'settleSeconds', 'blankPercent', 'jumpCells']
    out = []
    for k in keys:
        vals = [m[k] for m in ms if k in m]
        if vals:
            out.append(f"{short.get(k, k)}={statistics.median(vals):.2f}")
    print(f"{sc:<12}", ' '.join(out))
