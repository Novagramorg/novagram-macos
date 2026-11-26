import json
import sys

KEYS = ["pass", "finalProgress", "flips", "maxProgressStep", "maxDesyncPt", "stripTravelPt", "maxStripStepPt", "listTravelPt", "finalListOffset", "eventMsP50", "eventMsP95", "eventMsMax", "layoutMsP50", "layoutMsP95", "hitches", "worstGapMs"]

for path in sys.argv[1:]:
    report = json.load(open(path))
    print(f"== {report['label']}")
    print("scenario".ljust(28) + "".join(k[:9].rjust(10) for k in KEYS) + "  problems")
    for entry in report["entries"]:
        metrics = entry.get("metrics", {})
        notes = entry.get("notes", {})
        cells = []
        for key in KEYS:
            value = metrics.get(key)
            cells.append(("-" if value is None else f"{value:.2f}").rjust(10))
        print(entry["scenario"][:27].ljust(28) + "".join(cells) + "  " + notes.get("problems", notes.get("error", "")))
