#!/usr/bin/env python3
import sys, os

MARK = '@available(macOS 10.15, *)'


def main():
    if len(sys.argv) != 3:
        print('Usage: apply-ffi-availability.py MANIFEST GENERATED_SWIFT', file=sys.stderr)
        return 2
    manifest_path, source_path = sys.argv[1], sys.argv[2]
    wanted = set()
    with open(manifest_path) as handle:
        for raw in handle:
            entry = raw.rstrip('\n')
            if entry.strip() and not entry.startswith('#'):
                wanted.add(entry)
    lines = open(source_path).read().split('\n')
    seen = set()
    result = []
    inserted = 0
    for index, line in enumerate(lines):
        key = line.rstrip()
        if key in wanted:
            seen.add(key)
            if not (result and MARK in result[-1]):
                result.append(MARK)
                inserted += 1
        result.append(line)
    open(source_path, 'w').write('\n'.join(result))
    missing = sorted(wanted - seen)
    print('apply-ffi-availability: annotated %d declarations in %s' % (inserted, os.path.basename(source_path)))
    if missing:
        print('apply-ffi-availability: WARNING %d manifest entries no longer exist:' % len(missing), file=sys.stderr)
        for entry in missing[:20]:
            print('    %s' % entry.strip(), file=sys.stderr)
        if len(missing) > 20:
            print('    ... and %d more' % (len(missing) - 20), file=sys.stderr)
        print('apply-ffi-availability: the wallet-engine API changed; rebuild, then regenerate the', file=sys.stderr)
        print('manifest with the command recorded at the top of ffi-availability.txt', file=sys.stderr)
    if not seen:
        print('apply-ffi-availability: ERROR no manifest entry matched, manifest is stale', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
