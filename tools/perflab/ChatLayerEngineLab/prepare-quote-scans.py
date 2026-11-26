from pathlib import Path
import hashlib
import json

lab = Path(__file__).resolve().parent
reference = lab / 'Reference/quote-scan-preparation.swift.txt'
provenance = json.loads((lab / 'Reference/quote-scan-provenance.json').read_text())
assert hashlib.sha256(reference.read_bytes()).hexdigest() == provenance['sha256'], 'Quote scan reference changed'
source = reference.read_text()

def declaration(text, marker):
    start = text.index(marker)
    brace = text.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        if text[end] == '{':
            depth += 1
        elif text[end] == '}':
            depth -= 1
        end += 1
    return text[start:end]

prefix = declaration(source, '    private enum AttributeKeys') + '\n' + declaration(source, '    @inline(__always)')
simple = declaration(source, '    static func simpleText(').replace('func simpleText(', 'func referenceSimpleText(')
general = declaration(source, '    init(_ layout:')
general = general.replace('init(_ layout: FoldingTextLayout)', 'static func referencePresentation(_ layout: FoldingTextLayout) -> Self').replace('self.init(blocks:', 'return Self(blocks:')
bodies = {'ChatLayerEngine': prefix + '\n' + simple + '\n' + general, 'FoldingViewHarness': prefix + '\n' + simple}
for module, imports in [('ChatLayerEngine', 'import InputTextView'), ('FoldingViewHarness', '@testable import ChatLayerEngine')]:
    body = bodies[module].replace('AttributeKeys', 'ReferenceQuoteScanKeys').replace('func attribute(', 'func referenceQuoteScanAttribute(').replace('Self.attribute(', 'Self.referenceQuoteScanAttribute(')
    body = body.replace('text.hasBlockQuotes', '(text.attributedString.containsAttribute(attributeName: TextInputAttributes.quote) is TextViewBlockQuoteData)')
    destination = lab / 'Sources' / module / 'Generated/ReferenceQuoteScanPreparation.swift'
    destination.write_text('import Cocoa\nimport TGUIKit\n' + imports + '\n\nextension ChatLayerMessageTextPresentation {\n' + body + '\n}\n')
source = lab / 'Sources/FoldingViewHarness/Generated/LayerChatTextRow.swift'
destination = lab / 'Sources/FoldingViewHarness/Generated/ReferencePreparationChatTextRow.swift'
destination.write_text(source.read_text().replace('LayerChatTextRow', 'ReferencePreparationChatTextRow').replace('ChatLayerMessageTextPresentation.simpleText(', 'ChatLayerMessageTextPresentation.referenceSimpleText('))
