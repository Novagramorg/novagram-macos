from pathlib import Path
import shutil
import subprocess
import sys

experiment = Path(__file__).resolve().parent
lab = experiment.parents[1]
output = Path(sys.argv[1]).resolve()
subprocess.run([sys.executable, str(lab / 'prepare.py'), str(output)], check=True)
for name in ['ChatRowContentView.swift', 'LegacyHeaderHost.swift']:
    shutil.copyfile(experiment / (name + '.txt'), output / 'TextViewLayerLab/Sources/ChatTextRows' / name)
for name in ['HeaderTests.swift', 'HeaderMetalTests.swift', 'ViewSnapshot.swift']:
    shutil.copyfile(experiment / (name + '.txt'), output / 'TextViewLayerLab/Tests/LayerTests' / name)
