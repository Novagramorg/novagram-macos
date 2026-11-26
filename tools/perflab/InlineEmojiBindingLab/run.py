from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

snapshot = Path(sys.argv[1]).absolute()
scratch = Path(sys.argv[2]).absolute()
results = Path(sys.argv[3]).resolve()
assert not results.exists(), 'Use a new results directory'
results.mkdir(parents=True)
shutil.copyfile(__file__, results / 'runner.py')
(results / 'runner.sha256').write_text(hashlib.sha256(Path(__file__).read_bytes()).hexdigest() + '\n')
provenance = json.loads((snapshot / 'binding-provenance.json').read_text())

def verify():
    for value, digest in provenance['compiler_input_sha256'].items():
        assert hashlib.sha256(Path(value).read_bytes()).hexdigest() == digest, 'Compiler input changed: ' + value

def execute(arguments, name, environment=None):
    verify()
    with (results / name).open('w') as output:
        subprocess.run(arguments, stdout=output, stderr=subprocess.STDOUT, env=environment, check=True)
    verify()

def compiler_check(name):
    output = subprocess.run(['ps', '-axo', 'pid,comm'], capture_output=True, text=True, check=True).stdout
    active = '\n'.join(line for line in output.splitlines() if re.search(r'swift-frontend|xcodebuild|clang', line))
    (results / name).write_text(active + ('\n' if active else ''))
    assert not active, 'Competing compiler: ' + active

command = ['swift', 'test', '-c', 'release', '--package-path', str(snapshot), '--scratch-path', str(scratch)]
execute(command + ['--filter', 'BindingTests.testPreflight'], 'preflight.log')
records = []
for index, role in enumerate(['native', 'layer', 'layer', 'native']):
    environment = dict(os.environ, INLINE_EMOJI_BENCHMARK='1', INLINE_EMOJI_ROLE=role)
    name = '%02d-%s.log' % (index, role)
    compiler_check(name + '.pre.txt')
    execute(command + ['--skip-build', '--filter', 'BindingTests.testBenchmark'], name, environment)
    compiler_check(name + '.post.txt')
    lines = (results / name).read_text().splitlines()
    assert any(line.startswith('INLINE_EMOJI_PREFLIGHT ') for line in lines), 'No successful process preflight'
    run_records = [dict(json.loads(line.split(' ', 1)[1]), run=index) for line in lines if line.startswith('INLINE_EMOJI_BINDING ')]
    assert len(run_records) == 33, 'Missing benchmark phases'
    records.extend(run_records)
(results / 'measurements.json').write_text(json.dumps(records, indent=2) + '\n')
(results / 'binding-provenance.json').write_text(json.dumps(provenance, indent=2) + '\n')
print(results)
