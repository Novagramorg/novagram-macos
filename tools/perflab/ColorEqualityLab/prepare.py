from pathlib import Path
import hashlib
import json
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
baseline = '33863a272'
provenance = {'baseline': baseline, 'sources': {}}
for module, target, prefix, path in [('TGUIKit', 'KitProbe', 'kit', 'packages/TGUIKit/Sources/TGColor.swift'), ('Colors', 'CoreProbe', 'core', 'packages/Colors/Sources/Colors/Colors.swift')]:
    original = subprocess.check_output(['git', 'show', baseline + ':' + path], cwd=root, text=True)
    current = (root / path).read_text()
    start = original.index('    static func ==(lhs: NSColor, rhs: NSColor) -> Bool {')
    end = original.index('\n    }', start) + len('\n    }')
    reference = original[start:end].replace('    static func ==(lhs:', '@inline(never) public func ' + prefix + 'Reference(_ lhs:').replace(', rhs:', ', _ rhs:')
    argb_start = original.index('    var argb: UInt32 {')
    argb_end = original.index('\n    }', argb_start) + len('\n    }')
    assert original[argb_start:argb_end] in current
    output = 'import Cocoa\nimport ' + module + '\n\n' + reference + '\n'
    (lab / 'Sources' / target / 'Reference.swift').write_text(output)
    provenance['sources'][path] = {'original_sha256': hashlib.sha256(original.encode()).hexdigest(), 'candidate_sha256': hashlib.sha256(current.encode()).hexdigest(), 'reference_sha256': hashlib.sha256(output.encode()).hexdigest(), 'unchanged_argb_sha256': hashlib.sha256(original[argb_start:argb_end].encode()).hexdigest()}
style_path = 'packages/TGUIKit/Sources/Style.swift'
style = (root / style_path).read_text()
original_style = subprocess.check_output(['git', 'show', baseline + ':' + style_path], cwd=root, text=True)
predicate = 'return lhs.font == rhs.font && lhs.foregroundColor == rhs.foregroundColor && rhs.backgroundColor == lhs.backgroundColor'
assert predicate in style and predicate in original_style
reference_predicate = 'return lhs.font == rhs.font && kitReference(lhs.foregroundColor, rhs.foregroundColor) && kitReference(rhs.backgroundColor, lhs.backgroundColor)'
assert reference_predicate in (lab / 'Sources/KitProbe/Probe.swift').read_text()
provenance['style_predicate'] = {'source': style_path, 'source_sha256': hashlib.sha256(style.encode()).hexdigest(), 'predicate': predicate, 'reference_predicate': reference_predicate}
(lab / 'generation.json').write_text(json.dumps(provenance, indent=2) + '\n')
