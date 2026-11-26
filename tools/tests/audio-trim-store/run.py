import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
def block(source, marker):
    a=source.index(marker); b=source.index('{', a)+1; depth=1
    while depth:
        depth+=(source[b]=='{')-(source[b]=='}'); b+=1
    return source[a:b]
source = (Path('/tmp/AudioRecorder-before-audio-trim-store.swift') if args.baseline else root/'packages/TelegramMedia/Sources/AudioRecorder.swift').read_text()
data = (Path('/tmp/DataItem-before-audio-trim-store.swift') if args.baseline else root/'packages/TelegramMedia/Sources/DataItem.swift').read_text()
functions = '\n'.join(block(source, marker) for marker in ['public func temporaryMediaPath', 'public func trimOpusFile'])
methods = '\n'.join(block(source, marker).replace('private ', '') for marker in ['    func applyTrim(', '    private func replaceStore('])
common = Path(__file__).with_name('Context.swift').read_text().replace('__FUNCTIONS__', functions).replace('__METHODS__', methods)
builds = sorted(Path.home().glob('Library/Developer/Xcode/DerivedData/Telegram*/Build'), key=lambda p:p.stat().st_mtime, reverse=True)
build = next(p for p in builds if (p/'Products/Debug/OpusBinding.o').exists())
headers = root/'submodules/telegram-ios/submodules/OpusBinding/PublicHeaders'
with tempfile.TemporaryDirectory(prefix='audio-trim-store-') as directory:
    directory=Path(directory)
    module=directory/'Modules/OpusBinding'; module.mkdir(parents=True)
    (module/'module.modulemap').write_text('module OpusBinding { umbrella header '+json.dumps(str(headers/'OpusBinding/OpusBinding.h'))+' export * }\n')
    swift_args=['-I',str(module.parent),'-Xcc','-I'+str(headers)]
    encoder_source = Path('/tmp/opusenc-before-audio-trim-store.m') if args.baseline else root/'submodules/telegram-ios/submodules/OpusBinding/Sources/opusenc/opusenc.m'
    encoder_object = directory/'opusenc.o'
    sdk = subprocess.check_output(['xcrun', '--show-sdk-path', '--sdk', 'macosx'], text=True).strip()
    subprocess.run(['xcrun', 'clang', '-c', '-fobjc-arc', '-target', 'arm64-apple-macos10.13', '-isysroot', sdk, '-I'+str(headers/'OpusBinding'), '-I'+str(root/'core-xprojects/libopus/build/libopus/include'), '-I'+str(root/'submodules/telegram-ios/third-party/ogg/include'), '-I'+str(root/'submodules/telegram-ios/submodules/OpusBinding/Sources/opusenc'), str(encoder_source), '-o', str(encoder_object)], check=True)
    item_source = Path('/tmp/TGDataItem.m-before-opus-continuity') if args.baseline else root/'submodules/telegram-ios/submodules/OpusBinding/Sources/TGDataItem.m'
    item_object = directory/'TGDataItem.o'
    subprocess.run(['xcrun', 'clang', '-x', 'objective-c', '-c', '-fobjc-arc', '-target', 'arm64-apple-macos10.13', '-isysroot', sdk, '-I'+str(headers/'OpusBinding'), str(item_source), '-o', str(item_object)], check=True)
    objects = build/'Intermediates.noindex/OpusBinding.build/Debug/OpusBinding.build/Objects-normal/arm64'
    link_args = [str(p) for p in sorted(objects.glob('*.o')) if p.name not in ['opusenc.o', 'TGDataItem.o']] + [str(encoder_object), str(item_object), str(root/'core-xprojects/libopus/build/arm64/libopus.a')]
    manifest='''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "AudioTrimStore", targets: [
.testTarget(name: "ControlledTests", path: "ControlledTests"),
.testTarget(name: "NativeTests", path: "NativeTests", swiftSettings: [.unsafeFlags(SWIFT_ARGS)], linkerSettings: [.unsafeFlags(LINK_ARGS)])
])
'''.replace('SWIFT_ARGS',json.dumps(swift_args)).replace('LINK_ARGS',json.dumps(link_args))
    (directory/'Package.swift').write_text(manifest)
    for name in ['ControlledTests','NativeTests']:
        (directory/name).mkdir()
        prefix = 'import OpusBinding\n' if name=='NativeTests' else Path(__file__).with_name('ControlledBackend.swift').read_text()
        tests = Path(__file__).with_name(name+'.swift').read_text()
        (directory/name/'Tests.swift').write_text(prefix+'\n'+data.replace('import OpusBinding','')+'\n'+common+'\n'+tests)
    command=['swift','test','--package-path',str(directory),'--disable-sandbox','--jobs','4']
    raise SystemExit(subprocess.run(command, env=dict(os.environ,AUDIO_TRIM_BASELINE='1' if args.baseline else '0')).returncode)
