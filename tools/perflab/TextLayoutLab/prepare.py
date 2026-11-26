from pathlib import Path
import hashlib,json,shutil,sys
lab=Path(__file__).resolve().parent
root=lab.parents[2]
out=Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=True)
source=(root/'packages/TGUIKit/Sources/TextView.swift').read_text()
def segment(s,start,end):
    return start+s.split(start,1)[1].split(end,1)[0]
def extract(s):
    return '\n'.join([
        'import AppKit\nimport CoreText',
        segment(s,'private func combineIntersectingRectangles(', 'public struct TextInputAttributes'),
        segment(s,'public struct TextInputAttributes', 'public final class TextViewFormattedDateData'),
        segment(s,'func findClosestRect(', 'private var codeCopyIconCache'),
        segment(s,'public extension NSAttributedString.Key {\n    static let hexColorMark', 'private func drawFullCorner'),
        segment(s,'struct TextViewStrikethrough', 'private let defaultFont'),
        'private let defaultFont = NSFont.systemFont(ofSize: 13)',
        segment(s,'public final class TextViewLayout : Equatable {', '    func revealSpoiler()'),
        'public static func ==(lhs: TextViewLayout, rhs: TextViewLayout) -> Bool { lhs === rhs }',
    ])
def method(s,marker):
    start=s.index(marker); opening=s.index('{',start);depth=1;i=opening+1
    while depth:
        depth+=(s[i]=='{')-(s[i]=='}');i+=1
    return s[start:i]
def production(s):
    prefix=extract(s)
    return prefix+'\n'+method(s,'    public func setAttributedString(')+'\n'+method(s,'    public func dropLayoutSize(')+'\n'+method(s,'    func calculateLayout(')+'\n'+method(s,'    public func measure(')+'\n'+method(s,'    public func findIndex(')+'\n'+(lab/'Snapshot.swift.txt').read_text()+'\n}\n'
for name in ['Sources','Tests']:
    shutil.copytree(lab/name,out/name,dirs_exist_ok=True)
shutil.copy(lab/'Package.swift',out/'Package.swift')
for name,code in [('Baseline',(lab/'Fixtures/Baseline.swift.txt').read_text()),('Candidate',production(source))]:
    target=out/'Sources'/name;target.mkdir(parents=True,exist_ok=True)
    (target/'TextView.swift').write_text(code)
    shutil.copy(lab/'Support.swift.txt',target/'Support.swift')
prepared=root/'packages/TGUIKit/Sources/TextViewPreparedText.swift'
if prepared.exists():shutil.copy(prepared,out/'Sources/Candidate/TextViewPreparedText.swift')
helper=lab/'Experiments/LineRangeIndex.swift'
if helper.exists():shutil.copy(helper,out/'Sources/Candidate/TextViewLineRangeIndex.swift')
(out/'provenance.json').write_text(json.dumps({'sourceSHA256':hashlib.sha256(source.encode()).hexdigest(),'candidateExtractSHA256':hashlib.sha256(production(source).encode()).hexdigest(),'baselineSHA256':hashlib.sha256((lab/'Fixtures/Baseline.swift.txt').read_bytes()).hexdigest(),'preparedTextSHA256':hashlib.sha256(prepared.read_bytes()).hexdigest(),'supportSHA256':hashlib.sha256((lab/'Support.swift.txt').read_bytes()).hexdigest()},indent=2)+'\n')
