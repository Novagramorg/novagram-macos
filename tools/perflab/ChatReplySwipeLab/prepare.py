from pathlib import Path
import hashlib
import json
import subprocess
lab = Path(__file__).resolve().parent
root = lab.parents[2]
path = 'packages/ChatUI/Sources/ChatUI/ChatRowView.swift'
baseline = '4d6b34ae4'
original = subprocess.check_output(['git', 'show', baseline + ':' + path], cwd=root, text=True)
current = (root / path).read_text()
def generate(name, source):
    swipe = source[source.index('    private var swipingRightView:'):source.index('    public override var interactableView:')]
    if '    private func updateSwipeLayout(' in swipe:
        assert source[:source.index('    private var swipingRightView:')].count('        updateSwipeLayout(transition)') == 1
        layout = 'updateSwipeLayout(transition)'
    else:
        start = source.index('        if let delta = swipeDelta {')
        layout = source[start:source.index('\n        if let view = shareView {', start)]
    swipe = swipe.replace('ChatRowView', name).replace('public ', '').replace('NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)', 'recordHaptic()')
    return 'final class ' + name + ': RowEnvironment {\n' + swipe + '\nfunc layoutSwipe(_ transition: ContainedViewLayoutTransition = .immediate) {\n' + layout + '\n}\nvar swipeContainer: View? { swipingRightView }\n}\n'
control = current[current.index('public final class ChatSwipeToReplyView'):current.index('public class ChatRowView:')]
assert control == original[original.index('public final class ChatSwipeToReplyView'):original.index('public class ChatRowView:')]
control = control.replace('public ', '')
output = 'import Cocoa\nimport TGUIKit\n' + control + generate('NativeRow', original) + generate('CandidateRow', current)
(lab/'Tests/SwipeTests/Generated.swift').write_text(output)
(lab/'generation.json').write_text(json.dumps({'baseline': baseline, 'source_sha256': hashlib.sha256(current.encode()).hexdigest(), 'baseline_sha256': hashlib.sha256(original.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest(), 'scope': 'Production swipe control, row swipe fields/methods, and layout dispatch. Stand-in row shell/model/theme. Haptic hardware call replaced by a counter.'},indent=2)+'\n')
