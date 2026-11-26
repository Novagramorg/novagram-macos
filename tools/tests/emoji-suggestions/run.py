import argparse
import pathlib
import subprocess
import tempfile


parser = argparse.ArgumentParser()
parser.add_argument('--release', action='store_true')
parser.add_argument('--benchmark', action='store_true')
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[3]
fixtures = pathlib.Path(__file__).parent
source = (root / 'packages/ChatUI/Sources/ChatUI/ChatInterfaceStateContextQueries.swift').read_text()
start = source.index('private func recentEmojiSuggestions(')
end = source.index('\nprivate func makeInlineResult(', start)
implementation = source[start:end].replace('private func recentEmojiSuggestions', 'func recentEmojiSuggestions', 1)
start = source.index('Array($0 + $1.lazy.flatMap { pack in')
end = source.index('}.prefix(400))', start) + len('}.prefix(400))')
candidate_builder = source[start:end]
assert source.count(candidate_builder) == 2, 'Both candidate lists must stop at 400 featured files'
implementation += '''
func emojiCandidates(_ installed: [TelegramMediaFile.Accessor], _ featured: [FeaturedPack]) -> [TelegramMediaFile.Accessor] {
    let build: ([TelegramMediaFile.Accessor], [FeaturedPack]) -> [TelegramMediaFile.Accessor] = {
        ''' + candidate_builder + '''
    }
    return build(installed, featured)
}
'''
call = 'let suggestions = recentEmojiSuggestions(emojis: emojis.emojies, recentAnimated: emojis.animated, animated: animated)'
assert source.count(call) == 2, 'Both emoji suggestion paths must use the shared helper'
assert 'animated.filter({ $0.fileId == sort}).first' not in source
with tempfile.TemporaryDirectory(prefix='telegram-emoji-suggestions-') as directory:
    workspace = pathlib.Path(directory)
    (workspace / 'Implementation.swift').write_text(implementation)
    executable = workspace / 'tests'
    command = [
        'xcrun', 'swiftc', '-O' if args.release or args.benchmark else '-Onone',
        '-whole-module-optimization', '-module-cache-path', str(workspace / 'ModuleCache'),
        str(workspace / 'Implementation.swift'), str(fixtures / 'Fixtures.swift'),
        str(fixtures / 'Reference.swift'), str(fixtures / 'main.swift'), '-o', str(executable)
    ]
    subprocess.run(command, check=True)
    raise SystemExit(subprocess.run([str(executable)] + (['--benchmark'] if args.benchmark else [])).returncode)
