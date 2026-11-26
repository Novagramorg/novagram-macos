import argparse
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source',type=Path,default=root/'packages/StoriesUI/Sources/StoriesUI/StoryMediaController.swift')
args = parser.parse_args(); source = args.source.read_text()
a = source.index('private final class CollectionFilterRowView')
a = source.index('    override func set(item:',a); brace = source.index('{',a); depth = 1; end = brace + 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}'); end += 1
diff = (root/'packages/TGUIKit/Sources/MergeLists.swift').read_text().split('public func mergeListsStableWithUpdatesReversed')[0]
apply = (root/'packages/TGUIKit/Sources/ApplyMergedRows.swift').read_text().replace('import Cocoa','import Foundation').replace('public func applyMergedRows','func _applyMergedRows')
fixture = Path(__file__).with_name('StoryAlbumDragTests.swift').read_text().replace('__SET__',source[a:end]).replace('__DIFF__',diff).replace('__APPLY__',apply)
with tempfile.TemporaryDirectory(prefix='story-album-drag-') as directory:
    directory = Path(directory)
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StoryAlbumDrag", targets: [.testTarget(name: "StoryAlbumDragTests", path: "Tests")])
''')
    (directory/'Tests').mkdir(); (directory/'Tests/StoryAlbumDragTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']).returncode)
