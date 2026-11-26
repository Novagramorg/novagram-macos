from pathlib import Path
import hashlib
import json
import shutil
import subprocess

lab = Path(__file__).resolve().parent
root = lab.parents[2]
path = 'packages/StarsUI/Sources/StarsUI/StarsWidgets.swift'
source = (root / path).read_text()
original = subprocess.check_output(['git', 'show', '89aab78a1:' + path], cwd=root).decode()
def effects(text):
    return text[text.index('public final class StarsButtonEffectLayer:'):text.index('public struct Star_SliderAmount:')]
reference = (lab / 'Reference.swift.txt').read_text()
assert reference == effects(original)
fixed_reference = reference.replace('private static let whiteParticle: CGImage = BadgeStarsViewEffect.whiteParticle', 'private static let whiteParticle: CGImage = TelegramThemeHooks.shared.image(.starReactionParticle).precomposed(.white)')
output = 'import AppKit\nimport QuartzCore\nimport TGUIKit\n'
for prefix, code in [('Candidate', effects(source)), ('Reference', fixed_reference)]:
    output += code.replace('StarsButtonEffectLayer', prefix + 'Button').replace('BadgeStarsViewEffect', prefix + 'Badge')
output += reference[reference.index('public final class BadgeStarsViewEffect:'):].replace('BadgeStarsViewEffect', 'BrokenBadge')
for prefix, text in [('Candidate', source), ('Reference', original)]:
    for suffix, marker, effect in [('Slider', 'public final class Star_SliderView', 'Badge'), ('Bubble', 'public final class Star_BadgeView', 'Button')]:
        start = text.index('    public func updateColors(', text.index(marker))
        body = text[start:text.index('\n    }', start) + 6]
        initializer = '(frame: .zero)' if effect == 'Badge' else '()'
        output += f'public final class {prefix}{suffix} {{\n    public let foregroundLayer = SimpleGradientLayer()\n    public let effectLayer = {prefix}{effect}{initializer}\n{body}\n}}\n'
target = lab / 'Sources/Effects/Generated.swift'
target.parent.mkdir(parents=True, exist_ok=True)
target.write_text(output)
assets = {}
for original_name, name in [('star 22x22.png', 'star.png'), ('star 22x22@2x.png', 'star@2x.png')]:
    src = root / 'Telegram-Mac/Assets.xcassets/star_reaction_particle.imageset' / original_name
    dst = lab / 'Sources/Effects/Resources' / name
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)
    assets[name] = hashlib.sha256(src.read_bytes()).hexdigest()
(lab / 'provenance.json').write_text(json.dumps({'baseline': '89aab78a1', 'source_sha256': hashlib.sha256(source.encode()).hexdigest(), 'reference_sha256': hashlib.sha256(reference.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(output.encode()).hexdigest(), 'particle_sha256': assets, 'reference_repair': 'Replace only the self-referential BadgeStarsViewEffect.whiteParticle initializer with the production image hook and precomposition.'}, indent=2) + '\n')
