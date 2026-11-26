from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
contact = (root / "packages/TelegramLinks/Sources/TelegramLinks/ContactTokenLink.swift").read_text()
logic = (root / "packages/QrStudioUI/Sources/QrStudioUI/QrStudioCodePillLogic.swift").read_text()
state = logic[:logic.index("struct QrStudioShatter")]
start = logic.index("    static func menu(")
menu = logic[start:logic.index("    static func shatters(", start)]
source = contact + "\n" + state + "\nenum QrStudioBurn { static let refill: Double = 0.36\n" + menu + "}\n"
with tempfile.TemporaryDirectory(prefix="contact-free-links-") as directory:
    path = Path(directory) / "main.swift"
    path.write_text(source + Path(__file__).with_name("checks.swift").read_text())
    subprocess.run(["swift", "-module-cache-path", str(Path(directory) / "cache"), str(path)], check=True)
