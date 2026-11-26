#!/usr/bin/env python3
import re, sys

DECL = re.compile(r'^(?:public |private |fileprivate |internal |open )?(?:final |indirect )*(?:func|var|let|class|struct|enum|extension|protocol|actor|typealias)\b')
MARK = '@available(macOS 10.15, *)'

HEADER = (
    '# Declarations in the generated WalletEngineFFI.swift that must carry @available(macOS 10.15, *).\n'
    '# The generator emits none; build.sh replays them so WalletEngine keeps building for macOS 10.13.\n'
    '# Regenerate after an intentional API change, once the annotated file compiles:\n'
    '#   python3 core-xprojects/wallet-engine/wallet-engine/dump-ffi-availability.py \\\n'
    '#       packages/WalletEngine/Sources/WalletEngineFFI/WalletEngineFFI.swift > ffi-availability.txt\n'
)


def main():
    if len(sys.argv) != 2:
        print('Usage: dump-ffi-availability.py ANNOTATED_SWIFT', file=sys.stderr)
        return 2
    lines = open(sys.argv[1]).read().split('\n')
    entries = set()
    for index, line in enumerate(lines):
        if DECL.match(line) and index > 0 and MARK in lines[index - 1]:
            entries.add(line.rstrip())
    sys.stdout.write(HEADER + '\n'.join(sorted(entries)) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
