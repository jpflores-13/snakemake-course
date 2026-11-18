"""One QC table for all samples: reads after filtering, peaks, FRiP.

Called by the qc_summary rule with script:, so every file name comes
from the rule (snakemake.input, snakemake.params, snakemake.output).
"""
import subprocess

samples = snakemake.params.samples
peak_files = dict(zip(snakemake.params.peak_samples, snakemake.input.peaks))

rows = []
for sample, bam, flagstat in zip(samples, snakemake.input.bams,
                                 snakemake.input.flagstats):
    # first line of flagstat is "<n> + 0 in total ..."
    with open(flagstat) as fh:
        n_reads = int(fh.readline().split()[0])

    peaks = peak_files.get(sample)
    if peaks is None:
        n_peaks, frip = "NA", "NA"   # a control: no peaks by design
    else:
        with open(peaks) as fh:
            n_peaks = sum(1 for _ in fh)
        out = subprocess.run(["samtools", "view", "-c", "-L", peaks, bam],
                             capture_output=True, text=True, check=True)
        frip = f"{int(out.stdout) / n_reads:.4f}"

    rows.append((sample, n_reads, n_peaks, frip))

with open(snakemake.output[0], "w") as out:
    out.write("sample\treads_filtered\tn_peaks\tfrip\n")
    for row in sorted(rows):
        out.write("\t".join(str(x) for x in row) + "\n")
