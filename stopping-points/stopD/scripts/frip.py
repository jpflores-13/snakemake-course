"""Fraction of reads in peaks (FRiP) for one sample (rule frip).

Run by Snakemake's `script:` directive, so the `snakemake` object holds the rule's
input (filtered BAM and its peaks), output and log. A read counts as "in a peak"
when it overlaps a peak by at least 1 bp. ENCODE expects FRiP of 1% or more for
ChIP-seq; good CTCF data are often far above that.
"""
import bisect
import sys

import pysam

sys.stderr = open(snakemake.log[0], "w")


def read_peaks(path):
    """Peaks per chromosome as sorted, merged (start, end) lists (BED: 0-based, end-exclusive)."""
    by_chrom = {}
    with open(path) as fh:
        for line in fh:
            chrom, start, end = line.split("\t")[:3]
            by_chrom.setdefault(chrom, []).append((int(start), int(end)))
    merged = {}
    for chrom, intervals in by_chrom.items():
        intervals.sort()
        out = [list(intervals[0])]
        for start, end in intervals[1:]:
            if start <= out[-1][1]:          # overlaps the previous peak: extend it
                out[-1][1] = max(out[-1][1], end)
            else:
                out.append([start, end])
        merged[chrom] = ([s for s, _ in out], [e for _, e in out])
    return merged


peaks = read_peaks(snakemake.input.peaks)

reads = 0
in_peaks = 0
with pysam.AlignmentFile(snakemake.input.bam) as bam:
    for read in bam.fetch(until_eof=True):
        if read.is_unmapped:
            continue
        reads += 1
        if read.reference_name not in peaks:
            continue
        starts, ends = peaks[read.reference_name]
        ## the last peak that starts before the read ends; it overlaps if it ends after the read starts
        i = bisect.bisect_left(starts, read.reference_end) - 1
        if i >= 0 and ends[i] > read.reference_start:
            in_peaks += 1

frip = in_peaks / reads if reads else 0.0
with open(snakemake.output.tsv, "w") as out:
    out.write("sample\treads\treads_in_peaks\tfrip\n")
    out.write(f"{snakemake.wildcards.sample}\t{reads}\t{in_peaks}\t{frip:.4f}\n")
print(f"{snakemake.wildcards.sample}: {in_peaks} of {reads} reads in peaks (FRiP {frip:.4f})", file=sys.stderr)
