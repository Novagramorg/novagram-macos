from pathlib import Path
import argparse
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
platform = Path(subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-platform-path'], text=True).strip())
frameworks = platform / 'Developer/Library/Frameworks'
private_frameworks = platform / 'Developer/Library/PrivateFrameworks'
libraries = platform / 'Developer/usr/lib'
source_path = 'packages/InputDataUI/Sources/InputDataUI/InputDataControllerEntries.swift'
source = subprocess.check_output(['git', 'show', f'HEAD:{source_path}'], cwd=root, text=True) if args.baseline else (root / source_path).read_text()
entry_id = source[source.index('public enum InputDataEntryId'):source.index('public enum InputDataInputMode')]
identifier = source[source.index('open class InputDataIdentifier'):source.index('public enum InputDataValue')]
tests = (root / 'packages/InputDataUI/Tests/InputDataUITests/InputDataEntryIdTests.swift').read_text().replace('@testable import InputDataUI', '')
main = '''
import Foundation
import XCTest

let count = 3000
let keys = (0..<count).map { InputDataEntryId.custom(InputDataIdentifier("recipient_\\($0)")) }
var durations: [Double] = []
for _ in 0..<3 {
    let start = DispatchTime.now().uptimeNanoseconds
    var rows: [AnyHashable: Int] = [:]
    for (index, key) in keys.enumerated() { rows[key] = index }
    for index in 0..<count {
        precondition(rows[InputDataEntryId.custom(InputDataIdentifier("recipient_\\(index)"))] == index)
    }
    for key in keys { precondition(rows.removeValue(forKey: key) != nil) }
    durations.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
}
print("3000-row insert/lookup/remove median ms: \\(durations.sorted()[1])")
let suite = InputDataEntryIdTests.defaultTestSuite
suite.run()
guard let result = suite.testRun, result.executionCount == 4 else { fatalError("Missing identity tests") }
exit(result.hasSucceeded ? 0 : 1)
'''
failed = False
with tempfile.TemporaryDirectory(prefix='input-data-identity-') as directory:
    directory = Path(directory)
    (directory / 'Identity.swift').write_text(entry_id + identifier)
    (directory / 'Tests.swift').write_text(tests)
    (directory / 'main.swift').write_text(main)
    for optimization in ['-Onone', '-O']:
        executable = directory / 'tests'
        command = ['xcrun', 'swiftc', optimization, '-I', str(libraries), '-L', str(libraries), '-F', str(frameworks)]
        for path in [frameworks, private_frameworks, libraries]:
            command += ['-Xlinker', '-rpath', '-Xlinker', str(path)]
        command += ['-module-cache-path', str(directory / 'cache'), str(directory / 'Identity.swift'), str(directory / 'Tests.swift'), str(directory / 'main.swift'), '-o', str(executable)]
        subprocess.run(command, check=True)
        print(f'{"Baseline" if args.baseline else "Candidate"} {optimization}', flush=True)
        failed |= subprocess.run([str(executable)]).returncode != 0
raise SystemExit(int(failed))
