from pathlib import Path
import subprocess,hashlib,json,sys
lab=Path(__file__).resolve().parent
root=lab.parents[2]
path='packages/ChatUI/Sources/ChatUI/ReplyMarkupNode.swift'
baseline='9c2a08831'
original=subprocess.check_output(['git','show',baseline+':'+path],cwd=root,text=True)
current=(root/path).read_text()
output='import Cocoa\nimport TGUIKit\n'
output+=current[current.index('final class ReplyMarkupContainerView'):current.index('public class ReplyMarkupButtonLayout')]
for prefix,source in [('Reference',original),('Candidate',original if '--baseline' in sys.argv else current)]:
 body=source[source.index('private func replyMarkupRoundedPath'):]
 body=body.replace('ReplyMarkupNode',prefix+'ReplyMarkupNode').replace('replyMarkupRoundedPath',prefix+'RoundedPath')
 output+=body+'\n'
(lab/'Tests/MarkupTests/Generated.swift').write_text(output)
control=root/'packages/GeneralRows/Sources/GeneralRows/InteractiveTextView.swift'
source=control.read_text()
(lab/'Tests/MarkupTests/InteractiveTextView.swift').write_text('import Cocoa\nimport TGUIKit\n'+source[source.index('public final class InteractiveTextView'):])
(lab/'generation.json').write_text(json.dumps({'baseline':baseline,'sources':{path:hashlib.sha256(current.encode()).hexdigest(),str(control.relative_to(root)):hashlib.sha256(source.encode()).hexdigest()},'generated_sha256':hashlib.sha256(output.encode()).hexdigest(),'scope':'Complete ReplyMarkupNode and InteractiveTextView with real AppKit/TGUIKit. Button layout model, theme, account and inline renderer are fixtures.'},indent=2)+'\n')
