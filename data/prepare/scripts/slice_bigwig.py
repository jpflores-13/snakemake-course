"""Cut a bigWig down to one window.

Usage: python slice_bigwig.py <in.bw> <out.bw> <chrom> <start> <end>
start/end are 1-based and inclusive. Every interval of the input that
overlaps the window is copied with its value unchanged; intervals that
cross the window edge are clipped to the edge. The output header lists
only <chrom>, with its full length, so coordinates stay genomic.
"""

import sys

import pyBigWig


def main(src, dst, chrom, start, end):
    start0, end0 = int(start) - 1, int(end)
    bw = pyBigWig.open(src)
    length = bw.chroms(chrom)
    if length is None:
        sys.exit(f"{chrom} not in {src}")
    ivs = bw.intervals(chrom, start0, end0) or []
    bw.close()
    out = pyBigWig.open(dst, "w")
    out.addHeader([(chrom, length)], maxZooms=10)
    if ivs:
        starts = [max(s, start0) for s, _, _ in ivs]
        ends = [min(e, end0) for _, e, _ in ivs]
        values = [float(v) for _, _, v in ivs]
        out.addEntries([chrom] * len(ivs), starts, ends=ends, values=values)
    out.close()
    print(f"{dst}: {len(ivs)} intervals", file=sys.stderr)


if __name__ == "__main__":
    main(*sys.argv[1:])
