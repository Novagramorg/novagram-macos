from pathlib import Path
import hashlib
import json

lab = Path(__file__).resolve().parent
root = lab.parents[2]
paths = ["packages/TelegramMedia/Sources/AudioWaveform.swift", "packages/TelegramMedia/Sources/AudioWaveformView.swift"]
metadata = json.loads((lab / "Reference/hashes.json").read_text())
bridge = """
extension AudioWaveformView {
    func testProgress(_ progress: CGFloat) {
        updateRevealProgress(progress)
    }

    func testDraw(_ context: CGContext, foreground: Bool) {
        (foreground ? foregroundView : backgroundView).draw(in: context)
    }

    var testLayers: [CALayer] { [foregroundView, backgroundView] }
}
"""
cache_bridge = """
extension AudioWaveformDrawingSamples {
    var testSnapshot: ([UInt16], CGFloat)? {
        prepared.map { ($0.peaks, $0.inverseScale) }
    }
}
extension AudioWaveformContainerView {
    var testPreparation: AudioWaveformDrawingSamples { drawingSamples }
}
extension AudioWaveformView {
    var testSnapshot: ([UInt16], CGFloat)? { foregroundView.testPreparation.testSnapshot }
    var testSharedPreparation: Bool { foregroundView.testPreparation === backgroundView.testPreparation }
}
"""
provenance = {}
for module, baseline in [("WaveformCurrent", False), ("WaveformOriginal", True)]:
    chunks = []
    for path in paths:
        source = lab / "Reference" / (Path(path).name + ".txt") if baseline else root / path
        data = source.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        if baseline:
            assert metadata[Path(path).name] == digest
        provenance[str(source.relative_to(root))] = digest
        text = data.decode()
        if path.endswith("AudioWaveformView.swift"):
            text = text.split("private class DrawingLayer : SimpleLayer", 1)[0]
        chunks.append(text)
    output = "\n".join(chunks) + bridge + ("" if baseline else cache_bridge)
    target = lab / "Sources" / module / "Generated.swift"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(output)
    provenance[str(target.relative_to(root))] = hashlib.sha256(output.encode()).hexdigest()
(lab / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
