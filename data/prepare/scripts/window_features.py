"""Keep features that lie completely inside a window.

Usage: python window_features.py <bed|gtf> <in(.gz)> <chrom> <start> <end>
start/end are 1-based and inclusive (the config window).
BED uses 0-based half-open columns 2-3; GTF uses 1-based inclusive
columns 4-5. Header and comment lines are kept, feature lines are written
unchanged and sorted by start. Writes to stdout.
"""

import gzip
import sys


def main(fmt, path, chrom, start, end):
    start, end = int(start), int(end)
    opener = gzip.open if path.endswith(".gz") else open
    header, keep = [], []
    with opener(path, "rt") as fh:
        for line in fh:
            if line.startswith(("#", "track", "browser")):
                header.append(line)
                continue
            f = line.rstrip("\n").split("\t")
            if f[0] != chrom:
                continue
            if fmt == "bed":
                s1, e1 = int(f[1]) + 1, int(f[2])
            elif fmt == "gtf":
                s1, e1 = int(f[3]), int(f[4])
            else:
                sys.exit(f"unknown format {fmt}")
            if s1 >= start and e1 <= end:
                keep.append((s1, e1, line))
    keep.sort(key=lambda x: (x[0], x[1]))
    sys.stdout.writelines(header)
    sys.stdout.writelines(line for _, _, line in keep)


if __name__ == "__main__":
    main(*sys.argv[1:])
