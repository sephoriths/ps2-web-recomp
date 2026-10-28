import bisect
import collections
import re
import subprocess
import sys


def symbols(binary):
    out = subprocess.run(['nm', '-C', binary], capture_output=True, text=True, check=True).stdout
    table = []
    for line in out.splitlines():
        parts = line.split(' ', 2)
        if len(parts) == 3 and parts[0] and parts[1] in 'tTwW':
            table.append((int(parts[0], 16), parts[2]))
    table.sort()
    return [a for a, _ in table], [n for _, n in table]


def group(name):
    module = re.match(r'gen::m_([A-Za-z0-9_]+?)_unit_', name)
    if module:
        return 'game code: module ' + module.group(1)
    if name.startswith('gen::'):
        return 'game code: main program'
    if name.startswith('ps2::vu') or 'vu1_' in name:
        return 'runtime: VU'
    if name.startswith('ps2::gs') or name.startswith('ps2::gif'):
        return 'runtime: GS'
    if name.startswith('ps2::iop'):
        return 'runtime: IOP'
    return 'runtime: other'


def main():
    if len(sys.argv) < 3:
        print('usage: profile_report.py <ps2run binary> <file written by PS2_PROFILE> [rows]')
        return 1
    rows = int(sys.argv[3]) if len(sys.argv) > 3 else 20
    addrs, names = symbols(sys.argv[1])
    functions = collections.Counter()
    groups = collections.Counter()
    outside = []
    total = 0
    for line in open(sys.argv[2]):
        if line.startswith('#') or line.startswith('^'):
            continue
        if line.startswith('@'):
            outside.append(line.split(None, 2)[1:])
            continue
        address, hits = line.split()
        hits = int(hits)
        i = bisect.bisect_right(addrs, int(address, 16)) - 1
        name = names[i].split('(')[0] if i >= 0 else '?'
        functions[name] += hits
        groups[group(name)] += hits
        total += hits
    for hits, library in outside:
        groups['outside the binary'] += int(hits)
        total += int(hits)
    if not total:
        print('no samples')
        return 1
    print('%d samples' % total)
    for name, hits in groups.most_common():
        print('%6.1f%%  %s' % (hits * 100 / total, name))
    print()
    for name, hits in functions.most_common(rows):
        print('%6.1f%%  %s' % (hits * 100 / total, name[:110]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
