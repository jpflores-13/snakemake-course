#!/usr/bin/env python3
"""One QC table for all samples: reads after filtering, peaks, FRiP.

Run from the analysis folder after 03_filter.sh and 04_call_peaks.sh:
    python3 06_qc_summary.py
Writes qc_summary.tsv
"""
import glob
import os
import subprocess

rows = []
for bam in sorted(glob.glob("*.filt.bam")):
    sample = bam.removesuffix(".filt.bam")

    # first line of flagstat is "<n> + 0 in total ..."
    with open(f"{sample}.flagstat.txt") as fh:
        n_reads = int(fh.readline().split()[0])

    peaks = f"peaks/{sample}_peaks.narrowPeak"
    if os.path.exists(peaks):
        with open(peaks) as fh:
            n_peaks = sum(1 for _ in fh)
        # reads overlapping a peak
        out = subprocess.run(["samtools", "view", "-c", "-L", peaks, bam],
                             capture_output=True, text=True, check=True)
        frip = f"{int(out.stdout) / n_reads:.4f}"
    else:
        n_peaks, frip = "NA", "NA"   # controls have no peaks

    rows.append((sample, n_reads, n_peaks, frip))

with open("qc_summary.tsv", "w") as out:
    out.write("sample\treads_filtered\tn_peaks\tfrip\n")
    for row in rows:
        out.write("\t".join(str(x) for x in row) + "\n")

print(f"wrote qc_summary.tsv ({len(rows)} samples)")
