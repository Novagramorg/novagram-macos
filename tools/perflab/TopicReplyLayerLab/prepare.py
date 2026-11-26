from pathlib import Path
import hashlib
import json
import subprocess
import sys
import re
lab=Path(__file__).resolve().parent
root=lab.parents[2]
path='packages/ChatUI/Sources/ChatUI/TopicReplyItemView.swift'
baseline='6ecf012c1'
original=subprocess.check_output(['git','show',baseline+':'+path],cwd=root,text=True)
current=(root/path).read_text()
helper=current[current.index('struct ChatTopicIconIdentity:'):current.index('public final class TopicReplyItemLayout')]
output='import Cocoa\nimport TGUIKit\n'+helper
pre_identity=subprocess.check_output(['git','show','c31bc868a:'+path],cwd=root,text=True)
model_source = pre_identity if '--identity-baseline' in sys.argv else current
generated_id = re.search(r'fileId: (.+?), file: file, emoji:', model_source).group(1)
output += 'func fixtureGeneratedIconId(_ file: FixtureFile, _ threadData: FixtureTopicInfo) -> Int64 { ' + generated_id + ' }\n'
for name,source in [('NativeTopicView',original),('PreIdentityTopicView',pre_identity),('CandidateTopicView',pre_identity if '--identity-baseline' in sys.argv else current)]:
    body=source[source.index('public final class TopicReplyItemView'):].replace('public final class TopicReplyItemView', 'final class '+name).replace('public ','')
    frame = 'textView.frame' if name == 'NativeTopicView' else 'textLayer.frame.insetBy(dx: 2, dy: 3)'
    output+=body+'\nextension '+name+' {\nvar iconsForTesting: [InlineStickerItemLayer] { Array(inlineStickerItemViews.values) }\nvar textFrameForTesting: CGRect { '+frame+' }\n}\n'
(lab/'Tests/TopicTests/Generated.swift').write_text(output)
(lab/'generation.json').write_text(json.dumps({'baseline':baseline,'baseline_sha256':hashlib.sha256(original.encode()).hexdigest(),'source_sha256':hashlib.sha256(current.encode()).hexdigest(),'generated_sha256':hashlib.sha256(output.encode()).hexdigest(),'scope':'Complete native/current TopicReplyItemView with actual TGUIKit rendering; model/context and emoji decoding stand-ins.'},indent=2)+'\n')

binding_output='import Cocoa\nimport TGUIKit\n'
binding_hashes={}
for file,kind in [('ChatTopicSeparatorItem.swift','Separator'),('MonoforumVerticalView.swift','Vertical')]:
    binding_path='packages/ChatUI/Sources/ChatUI/'+file
    for name,source in [('Native'+kind,subprocess.check_output(['git','show','c31bc868a:'+binding_path],cwd=root,text=True)),('Candidate'+kind,(root/binding_path).read_text())]:
        if '--identity-baseline' in sys.argv and name.startswith('Candidate'):
            source=subprocess.check_output(['git','show','c31bc868a:'+binding_path],cwd=root,text=True)
        if kind=='Separator':
            start=source.index('            case let .topic(threadId, info):')+len('            case let .topic(threadId, info):')
            end=source.index('\n            }\n            \n            overlay',start)
            signature='func bind(_ info: FixtureTopicInfo, threadId: Int64, context: FixtureContext, animated: Bool = false)'
        else:
            start=source.rindex('            case let .topic(fileId):')+len('            case let .topic(fileId):')
            end=source.index('            case let .avatar(peer):',start)
            signature='func bind(_ item: FixtureVerticalItem, fileId: Int64, animated: Bool = false)'
        body=source[start:end]
        binding_output+='final class '+name+': '+kind+'Environment {\n'+signature+' {\n'+body+'\n}\n}\n'
        binding_hashes[name]=hashlib.sha256(body.encode()).hexdigest()
(lab/'Tests/TopicTests/GeneratedBindings.swift').write_text(binding_output)
(lab/'identity-generation.json').write_text(json.dumps({'baseline':'c31bc868a','blocks':binding_hashes,'generated_sha256':hashlib.sha256(binding_output.encode()).hexdigest(),'scope':'Exact topic icon-binding branches from separator and vertical topic views, with native View/InlineStickerView stand-ins for services.'},indent=2)+'\n')
