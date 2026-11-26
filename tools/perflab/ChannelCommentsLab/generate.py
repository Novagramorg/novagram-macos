from pathlib import Path
import hashlib
import json
import re
import sys

root = Path(sys.argv[1]).resolve()
output = Path(sys.argv[2]).resolve()
lab = root / 'tools/perflab/ChannelCommentsLab'
reference = lab / 'Reference/ChannelCommentsControls.swift.txt'
assert hashlib.sha256(reference.read_bytes()).hexdigest() == json.loads((lab / 'Reference/provenance.json').read_text())['sha256']
production = root / 'packages/ChatUI/Sources/ChatUI/ChannelCommentsControls.swift'
helper = root / 'packages/ChatUI/Sources/ChatUI/ChatReactionTextLayer.swift'
dropped = {'import Postbox', 'import SwiftSignalKit', 'import AvatarUI', 'import TelegramContext', 'import TelegramTheme'}

def strip_imports(text):
    lines = text.split('\n')
    kept = [line for line in lines if line.strip() not in dropped]
    assert len(lines) - len(kept) == len(dropped), 'Unexpected import set'
    return '\n'.join(kept)

legacy = strip_imports(reference.read_text())
for name in ['ChannelCommentsBubbleControl', 'ChannelCommentsSmallControl', 'CommentsBasicControl', 'ChannelCommentsRenderData', 'ChannelCommentRenderer']:
    legacy = re.sub(r'\b' + name + r'\b', 'Legacy' + name, legacy)
current = strip_imports(production.read_text())
folder = output / 'Sources/CommentsHarness'
folder.mkdir(parents=True, exist_ok=True)
(folder / 'Legacy.swift').write_text(legacy)
(folder / 'Current.swift').write_text(current)
(folder / helper.name).write_bytes(helper.read_bytes())
(output / 'generation-provenance.json').write_text(json.dumps({
    'reference_sha256': hashlib.sha256(reference.read_bytes()).hexdigest(),
    'production_sha256': hashlib.sha256(production.read_bytes()).hexdigest(),
    'helper_sha256': hashlib.sha256(helper.read_bytes()).hexdigest(),
    'changes': 'Removed Postbox/SwiftSignalKit/AvatarUI/TelegramContext/TelegramTheme imports (stand-ins in Stubs.swift); legacy public types prefixed with Legacy. No other edits.'
}, indent=2) + '\n')
