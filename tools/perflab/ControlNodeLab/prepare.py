from pathlib import Path

lab = Path(__file__).resolve().parent
root = lab.parents[2]
chat = root / 'packages/ChatUI/Sources/ChatUI'
real = lab / 'Sources/SceneLab/Generated'
mutant = lab / 'Sources/SceneLabMutant/Generated'
for folder in [real, mutant]:
    folder.mkdir(parents=True, exist_ok=True)
for name in ['ChatLayerScene.swift', 'ChatLayerControlNode.swift']:
    (real / name).write_bytes((chat / name).read_bytes())
(mutant / 'ChatLayerScene.swift').write_bytes((chat / 'ChatLayerScene.swift').read_bytes())
node = (chat / 'ChatLayerControlNode.swift').read_text()
marker = 'static let longPressDelay: Double = 0.35'
assert node.count(marker) == 1
(mutant / 'ChatLayerControlNode.swift').write_text(node.replace(marker, 'static let longPressDelay: Double = 0.2'))
for name in ['Stubs.swift', 'NodeHarness.swift']:
    (mutant / name).write_bytes((lab / 'Sources/SceneLab' / name).read_bytes())
