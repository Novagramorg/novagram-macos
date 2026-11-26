import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/StoriesUI/Sources/StoriesUI/StoryMediaController.swift')
args = parser.parse_args()
source = args.source.read_text()
def method(marker):
    start = source.index(marker); brace = source.index('{', start); depth = 1; end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}'); end += 1
    return source[start:end].replace('public override', 'override')
helper = method('    private func updateCollection(') if '    private func updateCollection(' in source else ''
fields = 'let collectionMutationDisposable = MetaDisposable()\nvar collectionMutationOperationId: UUID?\nvar acceptsCollectionMutation = true'
if helper:
    start = source.index('    private let collectionMutationDisposable')
    fields = source[start:source.index('    private let collectionsDisposable',start)].replace('private ','')
a = source.index('        let renameCollection:'); b = source.index('        let share:',a)
rename = source[a:b]
title = next(line.strip() for line in rename.splitlines() if 'var text: String =' in line)
a = rename.index('completion: {'); start = a + len('completion: '); brace = start; depth = 1; end = brace + 1
while depth:
    depth += (rename[end] == '{') - (rename[end] == '}'); end += 1
rename = 'self.renameConfirmed = ' + rename[start:end]
a = source.index('strings().storyMediaAlbumContextMenuDeleteConfirm')
a = source.index('successHandler: {',a); start = a + len('successHandler: '); depth = 1; end = start + 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}'); end += 1
delete = 'self.deleteConfirmed = ' + source[start:end]
if not helper:
    delete = delete.replace('{ _ in','{ [weak self] _ in',1)
a = source.index('actionsDisposable.add(combineLatest(queue: .mainQueue(), stateSignal, peer)')
a = source.index('            self.updateState {',a); brace = source.index('{',a); depth = 1; end = brace + 1
while depth:
    depth += (source[end] == '{') - (source[end] == '}'); end += 1
reducer = source[a:end]
create = method('    private func createCollection(') if '    private func createCollection(' in source else ''
a = source.index('    private func addCollection('); b = source.index('    private func ',a + 20)
add = source[a:b]
a = add.index('completion: {'); start = a + len('completion: '); depth = 1; end = start + 1
while depth:
    depth += (add[end] == '{') - (add[end] == '}'); end += 1
create_action = 'self.createConfirmed = ' + add[start:end]
if 'collectionMutationGeneration' in source:
    generation = 'let generation = self.collectionMutationGeneration\n'
    rename = generation + rename
    delete = generation + delete
    create_action = generation + create_action
if '    private func reorderCollections(' in source:
    reorder = method('    private func reorderCollections(').replace('private func','func',1)
else:
    a = source.index('        }, resort: { [weak self] from, to in'); b = source.index('        }, state:',a)
    action = source[a:b].replace('        }, resort:', 'let action: (Int, Int) -> Void =',1) + '\n}'
    reorder = 'func reorderCollections(from: Int64, to: Int64) {\nlet collections = self.state.collections\nguard let source = collections.firstIndex(where: { $0.stableId == from }), let target = collections.firstIndex(where: { $0.stableId == to }) else { return }\n' + action + '\naction(source,target)\n}'
membership_helper = method('    private func updateCollectionStories(') if '    private func updateCollectionStories(' in source else ''
a = source.index('        let addToCollection:'); b = source.index('        self.setCenterTitle(',a)
membership_action = source[a:b]
membership_action = 'self.addToCollection = ' + membership_action[membership_action.index('{ [weak self]'):]
contains = method('    func contains(collectionId:')
fixture = Path(__file__).with_name('StoryFolderMutationUITests.swift').read_text()
for key,value in [('__FIELDS__',fields),('__MEMBERSHIP_HELPER__',membership_helper),('__MEMBERSHIP_ACTION__',membership_action),('__CONTAINS__',contains),('__REORDER__',reorder),('__CREATE__',create),('__CREATE_ACTION__',create_action),('__UPDATE__',helper),('__TITLE__',title),('__RENAME_ACTION__',rename),('__DELETE_ACTION__',delete),('__REDUCER__',reducer),('__DISAPPEAR__',method('    public override func viewWillDisappear')),('__APPEAR__',method('    public override func viewWillAppear')),('__DEINIT__',method('    deinit {'))]: fixture=fixture.replace(key,value)
with tempfile.TemporaryDirectory(prefix='story-folder-mutation-ui-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "StoryFolderMutationUI", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "StoryFolderMutationUITests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/StoryFolderMutationUITests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
