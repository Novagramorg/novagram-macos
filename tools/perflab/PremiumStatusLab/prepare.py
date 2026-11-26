from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
observer_path = root / 'packages/PremiumStatusUI/Sources/PremiumStatusUI/PremiumStatusPeerObservation.swift'
control_path = root / 'packages/PremiumStatusUI/Sources/PremiumStatusUI/PremiumStatusControl.swift'
observer = observer_path.read_text().replace('import TelegramCore\n', '').replace('import Postbox\n', '')
control = control_path.read_text()
signature_start = control.index('    public func set(_ peer: Peer,')
signature = control[signature_start:control.index('\n', signature_start)].replace('public ', '')
start = control.index('        self.peerObservation.update(peer:')
end = control.index('\n        }', start) + len('\n        }')
binding = control[start:end]
assert 'private let peerObservation = PremiumStatusPeerObservation()' in control
assert 'combinedView(' not in control
assert 'self.disposable' not in control
old = subprocess.check_output(['git', 'show', '904aa8224:packages/PremiumStatusUI/Sources/PremiumStatusUI/PremiumStatusControl.swift'], cwd=root).decode()
start = old.index('        if autoupdate {')
end = old.index('\n        \n    }', start)
reference = (lab / 'Reference.swift.txt').read_text()
assert old[start:end].split() == reference.split()
reference = reference.replace('if autoupdate {', 'if enabled {')
old_call = 'self?.set(updated, account: account, inlinePacksContext: inlinePacksContext, left: left, color: color, isSelected: isSelected, isBig: isBig, animated: animated, playTwice: playTwice, isLite: isLite)'
assert old_call in reference
reference = reference.replace(old_call, 'if self != nil { onUpdate(updated) }')
output = observer + '\nfinal class ReferenceObservation {\n    private let disposable = MetaDisposable()\n    func update(peer: Peer, account: Account, enabled: Bool, onUpdate: @escaping (Peer) -> Void) {\n' + reference + '\n    }\n    deinit { disposable.dispose() }\n}\n'
output += '\nfinal class BindingControl {\n    let peerObservation = PremiumStatusPeerObservation()\n    var rendered: [Rendered] = []\n' + signature + '\n        rendered.append(Rendered(peer: peer, account: account, inlinePacksContext: inlinePacksContext, left: left, color: color, isSelected: isSelected, isBig: isBig, animated: animated, playTwice: playTwice, isLite: isLite, autoupdate: autoupdate))\n' + binding + '\n    }\n}\n'
output = 'import AppKit\n' + output
target = lab / 'Sources/Observation/Generated.swift'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(output)
(lab / 'provenance.json').write_text(json.dumps({'baseline': '904aa8224', 'observer_sha256': hashlib.sha256(observer_path.read_bytes()).hexdigest(), 'control_sha256': hashlib.sha256(control_path.read_bytes()).hexdigest(), 'reference_sha256': hashlib.sha256((lab / 'Reference.swift.txt').read_bytes()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest()}, indent=2) + '\n')
