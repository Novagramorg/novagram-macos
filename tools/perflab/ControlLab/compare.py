from pathlib import Path
import json
import statistics

evidence = Path(__file__).resolve().parent / "Evidence"
before = json.loads((evidence / "baseline.json").read_text())
after = json.loads((evidence / "candidate.json").read_text())
comparison = []
assert len(before["results"]) == len(after["results"])
for left, right in zip(before["results"], after["results"]):
    assert left["kind"] == right["kind"] and left["controls"] == right["controls"]
    row = {"kind": left["kind"], "controls": left["controls"]}
    for key in left["trials"][0]:
        old = statistics.median(t[key] for t in left["trials"])
        new = statistics.median(t[key] for t in right["trials"])
        row[key] = {"before": old, "after": new, "reductionPercent": 100 * (old - new) / old if old else None}
    comparison.append(row)
result = {"statistic": "median of seven trials", "results": comparison}
(evidence / "comparison.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
