from pathlib import Path
lab = Path(__file__).resolve().parent
root = lab.parents[2]
for name in ("PanelSearchPresentation", "PanelSearchStatusView"):
    source = root / f"packages/EntertainmentUI/Sources/EntertainmentUI/{name}.swift"
    (lab / f"Sources/SearchViews/Generated{name}.swift").write_bytes(source.read_bytes())
