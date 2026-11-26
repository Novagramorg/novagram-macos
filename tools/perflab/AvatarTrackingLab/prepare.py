from pathlib import Path
import hashlib
import json

lab = Path(__file__).resolve().parent
root = lab.parents[2]
production = root / 'packages/AvatarUI/Sources/AvatarUI/AvatarLayer.swift'
reference = lab / 'Reference/AvatarLayer.swift.txt'
expected = json.loads((lab / 'Reference/hashes.json').read_text())['AvatarLayer.swift']
assert hashlib.sha256(reference.read_bytes()).hexdigest() == expected

markers = [
    '    public init(font: NSFont)',
    '    public required init?(coder aDecoder: NSCoder)',
    '    public required override init(frame frameRect: NSRect)',
    '    open override func viewDidMoveToWindow()',
    '    open func set(handler:',
    '    override open func mouseEntered(with event: NSEvent)',
    '    open override func mouseDown(with event: NSEvent)',
    '    override open func mouseUp(with event: NSEvent)',
    '    open func removeAllHandlers()',
    '    open func send(event:ControlEvent)',
    '    open override func updateTrackingAreas()',
    '    open override func viewDidMoveToSuperview()',
    '    deinit {'
]

def declaration(source, marker):
    start = source.index(marker)
    cursor = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]

prefix = '''import Cocoa
import TGUIKit
import SwiftSignalKit

open class AvatarControl: NSView {
    private var trackingArea: NSTrackingArea?
    open var userInteractionEnabled = true
    private let longOverHandleDisposable = MetaDisposable()
    private let disposable = MetaDisposable()
    private var handlers: [(ControlEvent, (AvatarControl) -> Void)] = []
    open var font: NSFont
    public private(set) var imageDisplayNotifications = 0

    private func noteImageDisplayed() {
        imageDisplayNotifications += 1
    }

'''
provenance = {}
method_hashes = {}
for name, path in [('AvatarTrackingOriginal', reference), ('AvatarTrackingCurrent', production)]:
    data = path.read_bytes()
    source = data.decode()
    methods = [declaration(source, marker) for marker in markers]
    method_hashes[name] = {marker: hashlib.sha256(method.encode()).hexdigest() for marker, method in zip(markers, methods)}
    output = prefix + '\n\n'.join(methods) + '\n}\n'
    target = lab / 'Sources' / name / 'Generated.swift'
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(output)
    provenance[str(path)] = hashlib.sha256(data).hexdigest()
    provenance[str(target)] = hashlib.sha256(output.encode()).hexdigest()
(lab / 'provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
(lab / 'method-provenance.json').write_text(json.dumps(method_hashes, indent=2) + '\n')
