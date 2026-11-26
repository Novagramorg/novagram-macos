from pathlib import Path
import hashlib
import json

lab = Path(__file__).resolve().parent
root = lab.parents[2]
source = root / 'packages/InlineStickerLayer/Sources/InlineStickerLayer/InlineStickerPlayback.swift'
callers = [root / name for name in [
    'Telegram-Mac/packages-integration/hooks/GeneralRowsHooksInstall.swift',
    'packages/InputTextView/Sources/InputTextView/FoldingTextView.swift',
    'packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatAccessoryModel.swift'
]]
for caller in callers:
    text = caller.read_text()
    assert 'updateInlineStickerPlayback(' in text
    assert 'NSIntersectsRect(value.frame, superview.visibleRect)' not in text
reference = (lab / 'Reference.swift.txt').read_text()
generated = 'import TGUIKit\n' + source.read_text() + '\n' + reference
(lab / 'Sources/Playback/Generated.swift').write_text(generated)
(lab / 'provenance.json').write_text(json.dumps({'baseline': '7904949a9', 'source_sha256': {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [source] + callers}, 'reference_sha256': hashlib.sha256(reference.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(generated.encode()).hexdigest()}, indent=2) + '\n')
