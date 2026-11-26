from pathlib import Path
import hashlib,json,shutil,re,os
source=Path('/tmp/FormattedDateCheck').resolve();output=Path('/tmp/FormattedDateTiming').resolve();baseline=Path('/tmp/QuoteRedrawVerified').resolve()
assert not output.exists();output.mkdir()
for name in ['Sources','Tests','TGUIKit']:
 shutil.copytree(source/name,output/name,ignore=shutil.ignore_patterns('.build','.swiftpm'))
manifest=(source/'Package.swift').read_text().replace(str(source),str(output)).replace('/tmp/FormattedDateCheck','/tmp/FormattedDateTiming')
(output/'Package.swift').write_text(manifest)
provenance={}
for original,target in [('ChatLayerEngine','ChatLayerEngineBaseline'),('FoldingViewHarness','FoldingViewHarnessBaseline')]:
 shutil.rmtree(output/'Sources'/target)
 for p in (baseline/'Sources'/original).rglob('*'):
  if not p.is_file():continue
  data=p.read_bytes();target_path=output/'Sources'/target/p.relative_to(baseline/'Sources'/original);target_path.parent.mkdir(parents=True,exist_ok=True)
  s=data.decode().replace('ChatLayerEngine','ChatLayerEngineBaseline').replace('FoldingViewHarness','FoldingViewHarnessBaseline');target_path.write_text(s)
  provenance[str(p)]={'original_sha256':hashlib.sha256(data).hexdigest(),'renamed_sha256':hashlib.sha256(s.encode()).hexdigest(),'target':str(target_path.relative_to(output))}
p=output/'Tests/FoldingViewTests/FormattedDateBenchmarkTests.swift';s=p.read_text().replace('archived_pre_live_folding_baseline','immediate_pre_formatted_date_baseline');p.write_text(s)
(output/'date-baseline-provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
visited=set();files=set()
def collect(base):
 base=base.resolve()
 if base in visited:return
 visited.add(base);manifest=base/'Package.swift';files.add(manifest)
 for folder in ['Sources','Tests']:
  files.update(p for p in (base/folder).rglob('*') if p.is_file())
 for parent,dirs,names in os.walk(base):
  dirs[:]=[d for d in dirs if d not in ['.git','.build','.swiftpm','results','Reference','Experiments','experiments']]
  for name in names:
   p=Path(parent)/name
   if p.suffix in ['.swift','.m','.mm','.c','.h','.hpp','.metal','.modulemap'] or name=='module.modulemap':files.add(p)
 for value in re.findall(r'\.package\([^\n]*?path: "([^"]+)"',manifest.read_text()):collect(base/value)
collect(output)
inputs={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
Path('/tmp/formatted-date-timing-inputs.json').write_text(json.dumps(inputs,indent=2)+'\n')
print('Prepared immediate pre-date baseline;',len(provenance),'captured baseline files;',len(inputs),'compiler inputs')
