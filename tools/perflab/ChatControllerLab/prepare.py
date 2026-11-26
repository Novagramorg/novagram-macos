from pathlib import Path
import hashlib
import json
import shutil
import sys

lab = Path(__file__).resolve().parent
root = lab.parents[2]
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
for name in ('Sources', 'Tests'):
    shutil.copytree(lab / name, out / name, dirs_exist_ok=True)
shutil.copy(lab / 'Package.swift', out / 'Package.swift')
controller_path = root / 'packages/ChatUI/Sources/ChatUI/ChatController.swift'
helper_path = root / 'packages/ChatUI/Sources/ChatUI/ChatInitialRowSelection.swift'
source = controller_path.read_text()
assert 'self.updateScroller(state, onlyIfVisibilityChanged: true)' in source
assert 'private var scrollerTargetIsHidden: Bool?' in source

def between(value, start, end):
    return value.split(start, 1)[1].split(end, 1)[0]

def selection(value):
    start = '            var initialIndex:Int = 0'
    return start + between(value, start, '            var scrollState = state')

def remaining(value):
    start = '            messagesViewQueue.async {'
    return start + between(value, start, '        } else if let state = scrollToItem')

def scroller(value):
    start = '    func updateScroller('
    return start + between(value, start, '    public func inputChanged')

def wrap_selection(name, body):
    return '''
func select%s(_ rows: [TableRowItem], state: TableScrollState, viewport: CGFloat, measure: (TableRowItem) -> Void = { _ in }) -> Selection {
    let toView = HistoryView(filteredEntries: Array(rows.reversed()))
    let initialSize = NSSize(width: 480, height: viewport)
    let offset: CGFloat = 0
    func makeItem(_ item: TableRowItem) -> TableRowItem {
        measure(item)
        return item
    }
%s
    return Selection(start: initialIndex, insertions: firstInsertion)
}
''' % (name, body)

def wrap_remaining(name, body):
    return '''
func remaining%s(_ rows: [TableRowItem], selection: Selection, cancelled: Cancellation = Cancellation()) -> Subscriber {
    let entries = rows
    let initialIndex = selection.start
    let firstInsertion = selection.insertions
    let messagesViewQueue = ImmediateQueue()
    let subscriber = Subscriber()
    func makeItem(_ item: TableRowItem) -> TableRowItem { item }
%s
    return subscriber
}
''' % (name, body)

parts = ['import AppKit\nimport ScrollTypes']
for name, current in [('Baseline', False), ('Candidate', True)]:
    initial = selection(source) if current else (lab / 'Fixtures/initial-selection.swift.txt').read_text()
    tail = remaining(source) if current else (lab / 'Fixtures/remaining-transition.swift.txt').read_text()
    update = scroller(source) if current else (lab / 'Fixtures/scroller.swift.txt').read_text()
    parts += [wrap_selection(name, initial), wrap_remaining(name, tail)]
    parts += ['final class %sScroller: ScrollerFixture {\n%s\n}' % (name, update)]
parts += ['func baselineReveal(_ items: [RevealItem]) -> RevealView? { return items.compactMap { $0.view as? RevealView }.first(where: { $0.hasRevealState }) }']
reveal = 'let revealView = ' + between(source, 'let revealView = ', '\n            if let revealView = revealView')
reveal = reveal.replace('ChatRowView', 'RevealView')
parts += ['func candidateReveal(_ items: [RevealItem]) -> RevealView? {\n' + reveal + '\nreturn revealView\n}']
(out / 'Sources/LabCode/Extracted.swift').write_text('\n'.join(parts))
shutil.copy(helper_path, out / 'Sources/LabCode/ChatInitialRowSelection.swift')
provenance = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [controller_path, helper_path]}
(out / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')

table_path = root / 'packages/TGUIKit/Sources/TableView.swift'
table_source = table_path.read_text()
focus = 'public struct TableScrollFocus' + between(table_source, 'public struct TableScrollFocus', 'public enum TableScrollState')
(out / 'Sources/ScrollTypes').mkdir(exist_ok=True)
(out / 'Sources/ScrollTypes/TableScrollFocus.swift').write_text('import AppKit\n' + focus)
provenance[str(table_path.relative_to(root))] = hashlib.sha256(table_path.read_bytes()).hexdigest()
(out / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')

blocks = {"initialSelection": selection(source), "remainingTransition": remaining(source), "scroller": scroller(source), "reveal": reveal, "focus": focus, "centeredRows": helper_path.read_text()}
record = {"sourceSnapshotSHA256": provenance, "extractedBlockSHA256": {name: hashlib.sha256(value.encode()).hexdigest() for name, value in blocks.items()}, "note": "Source snapshot hashes describe the working tree. Extracted block hashes isolate tested code from unrelated pending edits elsewhere in the same files."}
(out / 'provenance.json').write_text(json.dumps(record, indent=2) + '\n')
