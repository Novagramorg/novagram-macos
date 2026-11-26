from pathlib import Path
import hashlib
import json
import re
import shutil
import subprocess
import sys

lab = Path(__file__).resolve().parent
root = lab.parents[2]
variant, destination = sys.argv[1:]
assert variant in ("baseline", "candidate")
destination = Path(destination)
kit = root / "packages/TGUIKit"
baseline = "4d3f1f417"
changed = ["TitleButton.swift"]

for name in ("Sources", "Tests"):
    target = destination / "TGUIKit" / name
    if target.exists():
        shutil.rmtree(target)
    shutil.copytree(kit / name, target)
manifest = (kit / "Package.swift").read_text()
manifest = re.sub(r'(\.package\(name: "[^"]+", path: ")([^"]+)', lambda m: m[1] + str((kit / m[2]).resolve()), manifest)
(destination / "TGUIKit/Package.swift").write_text(manifest)
if variant == "baseline":
    for name in changed:
        source = subprocess.check_output(["git", "show", f"{baseline}:packages/TGUIKit/Sources/{name}"], cwd=root)
        (destination / "TGUIKit/Sources" / name).write_bytes(source)

target = destination / "TextButtonLab/Sources"
if target.exists():
    shutil.rmtree(target)
shutil.copytree(lab / "Sources", target)
(destination / "TextButtonLab/Package.swift").write_text((lab / "Package.swift").read_text().replace("../../../packages/TGUIKit", "../TGUIKit"))
files = [destination / "TGUIKit/Sources" / name for name in changed]
files.append(destination / "TextButtonLab/Sources/TextButtonLab/main.swift")
provenance = {
    "variant": variant,
    "baselineCommit": baseline,
    "swift": subprocess.check_output(["swift", "--version"], text=True).strip(),
    "sha256": {str(p.relative_to(destination)): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
}
(destination / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
