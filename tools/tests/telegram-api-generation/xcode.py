from pathlib import Path
import json
import plistlib
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET


repository = Path(__file__).resolve().parents[3]
root = Path(tempfile.mkdtemp(prefix="telegram-api-xcode-"))
print("Integration fixture: " + str(root), flush=True)
(root / "Probe.xcodeproj/xcshareddata/xcschemes").mkdir(parents=True)
(root / "scripts").mkdir()
shutil.copy(repository / "scripts/prepare-telegram-api.py", root / "scripts/prepare-telegram-api.py")
for relative in ["submodules/telegram-ios/submodules/TelegramApi", "submodules/telegram-ios/build-system/SwiftTL"]:
    shutil.copytree(repository / relative, root / relative, ignore=shutil.ignore_patterns(".build", ".swiftpm", "SwiftPMGenerated"))
(root / "main.swift").write_text('import TelegramApi\nprint(Api.Peer.peerUser(.init(userId: 42)))\n')
project = json.loads(subprocess.check_output(["plutil", "-convert", "json", "-o", "-", str(repository / "Telegram.xcodeproj/project.pbxproj")]))
check_id = "CE4D72C9B2A34D84A52D6A02"
check_phase = project["objects"][check_id]
ids={s:f'{i:024X}' for i,s in enumerate(['project','group','products','main','product','target','sources','frameworks','mainbuild','pkgbuild','pkg','pkgproduct','projectconfigs','targetconfigs','projectconfig','targetconfig'],1)}
o={check_id: check_phase}
def obj(key,isa,**kw):o[ids[key]]=dict(isa=isa,**kw)
obj('project','PBXProject',attributes={},buildConfigurationList=ids['projectconfigs'],compatibilityVersion='Xcode 14.0',developmentRegion='en',hasScannedForEncodings=0,knownRegions=['en'],mainGroup=ids['group'],productRefGroup=ids['products'],projectDirPath='',projectRoot='',targets=[ids['target']],packageReferences=[ids['pkg']])
obj('group','PBXGroup',children=[ids['main'],ids['products']],sourceTree='<group>')
obj('products','PBXGroup',children=[ids['product']],name='Products',sourceTree='<group>')
obj('main','PBXFileReference',lastKnownFileType='sourcecode.swift',path='main.swift',sourceTree='<group>')
obj('product','PBXFileReference',explicitFileType='compiled.mach-o.executable',path='Probe',sourceTree='BUILT_PRODUCTS_DIR')
obj('target','PBXNativeTarget',buildConfigurationList=ids['targetconfigs'],buildPhases=[check_id,ids['sources'],ids['frameworks']],buildRules=[],dependencies=[],name='Probe',packageProductDependencies=[ids['pkgproduct']],productName='Probe',productReference=ids['product'],productType='com.apple.product-type.tool')
obj('sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=[ids['mainbuild']],runOnlyForDeploymentPostprocessing=0)
obj('frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[ids['pkgbuild']],runOnlyForDeploymentPostprocessing=0)
obj('mainbuild','PBXBuildFile',fileRef=ids['main'])
obj('pkgbuild','PBXBuildFile',productRef=ids['pkgproduct'])
obj('pkg','XCLocalSwiftPackageReference',relativePath='submodules/telegram-ios/submodules/TelegramApi')
obj('pkgproduct','XCSwiftPackageProductDependency',package=ids['pkg'],productName='TelegramApi')
for kind in ['project','target']:
    obj(kind+'configs','XCConfigurationList',buildConfigurations=[ids[kind+'config']],defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
obj('projectconfig','XCBuildConfiguration',buildSettings={'SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'12.0','SWIFT_VERSION':'5.0'},name='Debug')
obj('targetconfig','XCBuildConfiguration',buildSettings={'PRODUCT_NAME':'Probe','CODE_SIGNING_ALLOWED':'NO','ONLY_ACTIVE_ARCH':'YES'},name='Debug')
(root/'Probe.xcodeproj/project.pbxproj').write_bytes(plistlib.dumps(dict(archiveVersion='1',classes={},objectVersion='56',objects=o,rootObject=ids['project'])))

scheme = ET.parse(repository / "Telegram.xcodeproj/xcshareddata/xcschemes/Telegram.xcscheme")
for reference in scheme.findall(".//BuildableReference"):
    reference.set("BlueprintIdentifier", ids["target"])
    reference.set("BuildableName", "Probe")
    reference.set("BlueprintName", "Probe")
    reference.set("ReferencedContainer", "container:Probe.xcodeproj")
scheme.write(root / "Probe.xcodeproj/xcshareddata/xcschemes/Probe.xcscheme", encoding="utf-8", xml_declaration=True)

def run(command, name, success=True):
    with (root / (name + ".log")).open("w") as log:
        result = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT)
    if success != (result.returncode == 0):
        print((root / (name + ".log")).read_text()[-12000:])
        raise RuntimeError(name + " returned " + str(result.returncode))
    print(name + ": passed", flush=True)

prepare = ["python3", str(root / "scripts/prepare-telegram-api.py")]
run(prepare, "clean-preflight")
build = ["xcodebuild", "-project", str(root / "Probe.xcodeproj"), "-scheme", "Probe", "-derivedDataPath", str(root / "DerivedData"), "-destination", "platform=macOS", "ONLY_ACTIVE_ARCH=YES", "build"]
run(build, "clean-build")
product = root / "DerivedData/Build/Products/Debug/Probe"
assert subprocess.check_output([str(product)], text=True).strip() == "peerUser"
api = root / "submodules/telegram-ios/submodules/TelegramApi"
output = api / "Sources/SwiftPMGenerated/Api0.swift"
modified = output.stat().st_mtime_ns
run(build, "incremental-build")
assert output.stat().st_mtime_ns == modified
schema = api / "swift_scheme.tl"
schema.write_text(schema.read_text() + "\n")
run(build, "schema-update-build")
run(prepare + ["--check"], "updated-check")
script = api / "generate-swiftpm.sh"
script.write_text(script.read_text() + "\nexit 37\n")
run(build, "failed-generator-build", success=False)
log = (root / "failed-generator-build.log").read_text()
assert "error: TelegramApi generation:" in log
assert subprocess.check_output([str(product)], text=True).strip() == "peerUser"
print("All Xcode integration checks passed; logs: " + str(root), flush=True)
