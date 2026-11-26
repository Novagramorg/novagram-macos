import plistlib
import subprocess

from test_incremental import ArchiveTests, write


fixture = ArchiveTests()
fixture.setUp()
source = fixture.source
objects = {}
names = ["project", "group", "products", "main", "product", "target", "sources", "mainbuild", "projectconfigs", "targetconfigs", "projectconfig", "targetconfig"]
ids = {name: f"{index:024X}" for index, name in enumerate(names, 1)}


def obj(key, kind, **values):
    objects[ids[key]] = dict(isa=kind, **values)


obj("project", "PBXProject", attributes={}, buildConfigurationList=ids["projectconfigs"], compatibilityVersion="Xcode 14.0", developmentRegion="en", knownRegions=["en"], mainGroup=ids["group"], productRefGroup=ids["products"], projectDirPath="", projectRoot="", targets=[ids["target"]])
obj("group", "PBXGroup", children=[ids["main"], ids["products"]], sourceTree="<group>")
obj("products", "PBXGroup", children=[ids["product"]], name="Products", sourceTree="<group>")
obj("main", "PBXFileReference", lastKnownFileType="sourcecode.swift", path="main.swift", sourceTree="<group>")
obj("product", "PBXFileReference", explicitFileType="wrapper.application", path="Telegram.app", sourceTree="BUILT_PRODUCTS_DIR")
obj("target", "PBXNativeTarget", buildConfigurationList=ids["targetconfigs"], buildPhases=[ids["sources"]], buildRules=[], dependencies=[], name="Telegram", productName="Telegram", productReference=ids["product"], productType="com.apple.product-type.application")
obj("sources", "PBXSourcesBuildPhase", buildActionMask=2147483647, files=[ids["mainbuild"]], runOnlyForDeploymentPostprocessing=0)
obj("mainbuild", "PBXBuildFile", fileRef=ids["main"])
for kind in ["project", "target"]:
    obj(kind + "configs", "XCConfigurationList", buildConfigurations=[ids[kind + "config"]], defaultConfigurationIsVisible=0, defaultConfigurationName="Release")
obj("projectconfig", "XCBuildConfiguration", buildSettings={"SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "12.0", "SWIFT_VERSION": "5.0", "SWIFT_COMPILATION_MODE": "wholemodule", "SWIFT_OPTIMIZATION_LEVEL": "-O", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym", "ARCHS": "arm64 x86_64", "ONLY_ACTIVE_ARCH": "NO"}, name="Release")
obj("targetconfig", "XCBuildConfiguration", buildSettings={"PRODUCT_NAME": "Telegram", "PRODUCT_BUNDLE_IDENTIFIER": "org.telegram.ci-build-smoke", "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGNING_ALLOWED": "NO", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "PRODUCTION"}, name="Release")
project = source / "Telegram.xcodeproj"
project.mkdir()
(project / "project.pbxproj").write_bytes(plistlib.dumps(dict(archiveVersion="1", classes={}, objectVersion="56", objects=objects, rootObject=ids["project"])))
write(source / "main.swift", 'import Foundation\n#if BETA\nprint("BETA")\n#else\nprint("wrong channel")\n#endif\n')
write(source / "Telegram-Mac.xcworkspace/contents.xcworkspacedata", '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="group:Telegram.xcodeproj"/></Workspace>\n')
write(project / "xcshareddata/xcschemes/Release.xcscheme", f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
<BuildActionEntry buildForArchiving="YES" buildForRunning="YES" buildForTesting="YES" buildForProfiling="YES" buildForAnalyzing="YES">
<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ids['target']}" BuildableName="Telegram.app" BlueprintName="Telegram" ReferencedContainer="container:Telegram.xcodeproj"/>
</BuildActionEntry></BuildActionEntries></BuildAction>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="NO"/>
</Scheme>''')
wrapper = fixture.root / "bin/xcodebuild"
wrapper.write_text('#!/bin/sh\nexec /usr/bin/xcodebuild "$@" -derivedDataPath "$SMOKE_DERIVED_DATA"\n')
fixture.environment["SMOKE_DERIVED_DATA"] = str(fixture.root / "DerivedData")
print("Xcode archive smoke fixture: " + str(fixture.root), flush=True)

try:
    for name, options in [("baseline", {}), ("cache-enabled", {"TELEGRAM_COMPILATION_CACHE": "YES"}), ("cache-repeat", {"TELEGRAM_COMPILATION_CACHE": "YES"})]:
        result = fixture.build(**options)
        write(fixture.root / (name + ".log"), result.stdout + result.stderr)
        output = fixture.root / "builds/build-Beta/Telegram.app/Contents/MacOS/Telegram"
        subprocess.run(["lipo", str(output), "-verify_arch", "arm64", "x86_64"], check=True)
        assert subprocess.check_output([str(output)], text=True).strip() == "BETA"
        assert (fixture.root / "builds/build-Beta/Telegram.app.DSYM.zip").is_file()
        print(name + ": universal archive, channel condition and dSYM verified", flush=True)
except subprocess.CalledProcessError as error:
    print(error.stdout or "")
    print(error.stderr or "")
    raise
finally:
    fixture.doCleanups()
