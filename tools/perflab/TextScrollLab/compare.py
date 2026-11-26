from pathlib import Path
import hashlib
import json
import statistics

root = Path(__file__).resolve().parent / "Evidence"
before = json.loads((root / "baseline.json").read_text())
after = json.loads((root / "candidate.json").read_text())
assert len(before["results"]) == len(after["results"])
rows = []
for left, right in zip(before["results"], after["results"]):
    assert left["kind"] == right["kind"] and left["operations"] == right["operations"]
    row = {"kind": left["kind"], "operations": left["operations"]}
    for metric in ["trialsMs", "cpuTrialsMs"]:
        if metric not in left:
            continue
        assert len(left[metric]) == len(right[metric]) == 7
        old = statistics.median(left[metric])
        new = statistics.median(right[metric])
        row[metric] = {"baselineMedian": old, "candidateMedian": new, "reductionPercent": (1 - new / old) * 100}
    rows.append(row)
images = []
for baseline in sorted((root / "baseline-snapshots").glob("*.rgba")):
    candidate = root / "candidate-snapshots" / baseline.name
    assert baseline.read_bytes() == candidate.read_bytes(), baseline.name
    pixels = baseline.read_bytes()
    assert sum(pixels[i + 3] > 0 and max(pixels[i:i + 3]) < 200 for i in range(0, len(pixels), 4)) > 30, baseline.name
    images.append({"name": baseline.name, "sha256": hashlib.sha256(baseline.read_bytes()).hexdigest(), "differentBytes": 0})
assert len(images) == 6
geometry = (root / "baseline-snapshots/table-geometry.json").read_bytes()
assert geometry == (root / "candidate-snapshots/table-geometry.json").read_bytes()
assert len(json.loads(geometry)) == 42
result = {"statistic": "median of seven trials", "results": rows, "pixelComparisons": images, "matchingTableGeometryCheckpoints": 42}
(root / "comparison.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))

repeat_paths = [root / f"{variant}-repeat.json" for variant in ["baseline", "candidate"]]
if all(path.exists() for path in repeat_paths):
    baseline_repeat, candidate_repeat = [json.loads(path.read_text()) for path in repeat_paths]
    repeated = []
    for left, right in zip(baseline_repeat["results"], candidate_repeat["results"]):
        assert left["kind"] == right["kind"] and left["operations"] == right["operations"]
        row = {"kind": left["kind"]}
        for metric in ["trialsMs", "cpuTrialsMs"]:
            if metric in left:
                old = statistics.median(left[metric])
                new = statistics.median(right[metric])
                row[metric] = {"baselineMedian": old, "candidateMedian": new, "reductionPercent": (1 - new / old) * 100}
        repeated.append(row)
    (root / "repeat-comparison.json").write_text(json.dumps({"order": ["candidate", "baseline"], "statistic": "median of seven trials", "results": repeated}, indent=2) + "\n")
