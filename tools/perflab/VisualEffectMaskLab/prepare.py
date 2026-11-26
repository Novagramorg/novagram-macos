from pathlib import Path
import hashlib
import json
lab = Path(__file__).resolve().parent
root = lab.parents[2]
s = (root / 'packages/ChatUI/Sources/ChatUI/ChatRowView.swift').read_text()
a = s.index('    private func applyCutBands(')
b = s.index('    public func shakeContentView()', a)
current = s[a:b].replace('private func applyCutBands', 'func applyCutBands').rstrip()
old = (lab / 'Reference/flat-mask-original.txt').read_text().rstrip()
new = (lab / 'Reference/flat-mask-candidate.txt').read_text().rstrip()
assert current.count(new) == 1
baseline = current.replace(new, old)
for name, module, body in [('Candidate', 'TGUIKit', current), ('Reference', 'TGUIKitBaseline', baseline)]:
    template = (lab / 'HostTemplate.txt').read_text()
    result = template.replace('MODULE', module).replace('HOST', name + 'PanelHost').replace('BODY', body)
    (lab / 'Tests/MaskTests' / (name + 'PanelHost.swift')).write_text(result)
(lab / 'generation.json').write_text(json.dumps({'apply_cut_bands_sha256': hashlib.sha256(current.encode()).hexdigest(), 'visual_effect_sha256': hashlib.sha256((root / 'packages/TGUIKit/Sources/VisualEffectView.swift').read_bytes()).hexdigest()}, indent=2) + '\n')
