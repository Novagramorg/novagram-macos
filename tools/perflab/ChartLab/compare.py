import json, sys, glob, os, statistics
rows = []
for path in glob.glob(os.path.join(sys.argv[1], "*.jsonl")):
    for line in open(path):
        line = line.strip()
        if line:
            rows.append(json.loads(line))
groups = {}
for row in rows:
    groups.setdefault((row["chart"], row["scenario"]), {}).setdefault(row["label"], []).append(row)
keys = ["cpuCores", "mainThreadBusyPercent", "drawsPerSecond", "hitches", "worstGapMs", "openMs"]
print(f"{'chart':<12}{'scenario':<9}" + "".join(f"{k:>26}" for k in keys))
for (chart, scenario) in sorted(groups):
    g = groups[(chart, scenario)]
    if "Legacy" not in g or "Current" not in g:
        continue
    cells = []
    for k in keys:
        l = statistics.median(r[k] for r in g["Legacy"])
        c = statistics.median(r[k] for r in g["Current"])
        cells.append(f"{l:>11.2f} -> {c:<11.2f}")
    print(f"{chart:<12}{scenario:<9}" + "".join(f"{c:>26}" for c in cells))
