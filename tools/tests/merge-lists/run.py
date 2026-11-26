import argparse
import os
import pathlib
import shutil
import subprocess
import tempfile


parser = argparse.ArgumentParser()
parser.add_argument('--configuration', choices=['debug', 'release'], default='debug')
parser.add_argument('--benchmark', action='store_true')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[3]
fixtures = root / 'packages/TGUIKit/Tests/TGUIKitTests'

with tempfile.TemporaryDirectory(prefix='telegram-merge-lists-') as directory:
    package = pathlib.Path(directory)
    for folder in ['Sources/TGUIKit', 'Sources/MergeListsReference', 'Sources/MergeListsBenchmark', 'Tests']:
        (package / folder).mkdir(parents=True)
    (package / 'Package.swift').write_text('''// swift-tools-version:5.5
import PackageDescription
let package = Package(
    name: "MergeListsRegression",
    platforms: [.macOS(.v10_13)],
    targets: [
        .target(name: "TGUIKit"),
        .target(name: "MergeListsReference", dependencies: ["TGUIKit"]),
        .executableTarget(name: "MergeListsBenchmark", dependencies: ["TGUIKit", "MergeListsReference"]),
        .testTarget(name: "MergeListsTests", dependencies: ["TGUIKit"], path: "Tests")
    ]
)
''')
    shutil.copy2(root / 'packages/TGUIKit/Sources/MergeLists.swift', package / 'Sources/TGUIKit')
    for name in ['MergeListsReference.swift', 'MergeListsTests.swift']:
        shutil.copy2(fixtures / name, package / 'Tests')
    reference = (fixtures / 'MergeListsReference.swift').read_text()
    (package / 'Sources/MergeListsReference/MergeListsReference.swift').write_text(
        reference.replace('func referenceMergeListsStableWithUpdates', 'public func referenceMergeListsStableWithUpdates', 1)
    )
    shutil.copy2(pathlib.Path(__file__).with_name('Benchmark.swift'), package / 'Sources/MergeListsBenchmark/main.swift')
    options = ['--package-path', directory, '--cache-path', str(package / 'Cache'), '--config-path', str(package / 'Configuration'), '--security-path', str(package / 'Security'), '--disable-sandbox']
    if args.benchmark:
        command = ['swift', 'run', *options, '-c', 'release', 'MergeListsBenchmark']
    else:
        command = ['swift', 'test', *options, '-c', args.configuration]
    environment = os.environ.copy()
    environment['CLANG_MODULE_CACHE_PATH'] = str(package / 'ModuleCache')
    environment['SWIFT_MODULECACHE_PATH'] = str(package / 'ModuleCache')
    print(f'Running isolated merge-list {"benchmark" if args.benchmark else "tests"}: {directory}', flush=True)
    raise SystemExit(subprocess.run(command, env=environment).returncode)
