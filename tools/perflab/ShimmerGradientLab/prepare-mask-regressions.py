from pathlib import Path
import gzip
import shutil
import subprocess
import sys

lab = Path(__file__).resolve().parent
mask_lab = lab.parent / 'ShimmerRenderLab'
output = Path(sys.argv[1]).resolve()
assert output.is_relative_to(Path('/tmp').resolve()) and not output.exists()
subprocess.run([sys.executable, str(lab / 'prepare-isolated.py'), str(output)], check=True)
shutil.rmtree(output / 'Tests')
shutil.copytree(mask_lab / 'Tests', output / 'Tests')
manifest = (mask_lab / 'Package.swift').read_text().replace('../../../packages/TGUIKit', str(output / 'TGUIKit'))
(output / 'Package.swift').write_text(manifest)
for module in ['TGUIKit', 'TGUIKitBaseline']:
    for name in ['ShimmerLayer.swift', 'StickerShimmerEffectView.swift']:
        path = output / module / 'Sources' / name
        if module == 'TGUIKitBaseline':
            source = gzip.decompress((mask_lab / 'Reference' / (name + '.gz')).read_bytes()).decode()
        else:
            source = path.read_text()
        path.write_text(source + (mask_lab / (name + '.inspection.txt')).read_text())
    path = output / module / 'Sources/DrawingContext.swift'
    source = path.read_text()
    marker = 'public func generateImage(_ size: CGSize, opaque: Bool = false, scale: CGFloat? = System.backingScale, rotatedContext: (CGSize, CGContext) -> Void) -> CGImage? {\n'
    assert source.count(marker) == 1
    source = source.replace(marker, marker + '    let completeProbe = ShimmerRasterProbe.begin(size)\n    defer { completeProbe?() }\n')
    path.write_text(source + (mask_lab / 'RasterProbe.swift.txt').read_text())
