from pathlib import Path
import hashlib
import json

lab = Path(__file__).resolve().parent
root = lab.parents[2]
source = root / 'packages/InputTextView/Sources/InputTextView/FoldingTextView.swift'
key_source = root / 'packages/TGUIKit/Sources/TextView.swift'
text = source.read_text()
method = text[text.index('    public static func breakString('):text.index('    public static func make(', text.index('    public static func breakString('))]
key = next(line for line in key_source.read_text().splitlines() if 'public static let quote = NSAttributedString.Key' in line)
reference = (lab / 'Reference.swift.txt').read_text()
output = 'import Foundation\n\nenum TextInputAttributes {\n' + key + '\n}\n'
output += 'enum CurrentSplit {\n' + method + '}\nenum ReferenceSplit {\n' + reference + '}\n'
(lab / 'Sources/TextSplit').mkdir(parents=True, exist_ok=True)
(lab / 'Sources/TextSplit/Generated.swift').write_text(output)
(lab / 'provenance.json').write_text(json.dumps({'baseline': 'a878b977c', 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'quote_key_sha256': hashlib.sha256(key.encode()).hexdigest(), 'reference_sha256': hashlib.sha256(reference.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest()}, indent=2) + '\n')
