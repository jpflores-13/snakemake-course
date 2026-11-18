"""One QC table across all samples (rule qc_table).

Run by Snakemake's `script:` directive. Columns:
  reads_in        reads in the FASTQ (= primary records in the aligned BAM; bowtie2 keeps unaligned reads)
  reads_aligned   ... of them aligned
  pct_aligned     reads_aligned / reads_in, in %
  reads_filtered  reads left after MAPQ, flag, blacklist and duplicate filtering (from frip / markdup)
  duplicate_rate  duplicates / reads examined by samtools markdup
  peaks           MACS3 peaks (NA for controls)
  frip            fraction of reads in peaks (NA for controls)
"""
import sys

import pandas as pd

sys.stderr = open(snakemake.log[0], "w")


def flagstat(path):
    """samtools flagstat -O tsv: value, QC-failed value, category. Returns {category: value}."""
    tab = pd.read_csv(path, sep="\t", header=None, names=["value", "qcfail", "category"], dtype=str)
    return dict(zip(tab["category"], tab["value"]))


def markdup_stats(path):
    """samtools markdup -f: lines like 'EXAMINED: 12345'. Returns {key: int}."""
    stats = {}
    with open(path) as fh:
        for line in fh:
            key, sep, value = line.partition(":")
            if sep and value.strip().lstrip("-").isdigit():
                stats[key.strip()] = int(value)
    return stats


samples = snakemake.params.samples
peak_samples = snakemake.params.peak_samples
## Inputs are lists in the same order as the sample lists (expand keeps the order)
flagstats = dict(zip(samples, snakemake.input.flagstat))
markdups = dict(zip(samples, snakemake.input.markdup))
frips = dict(zip(peak_samples, snakemake.input.frip))
peak_files = dict(zip(peak_samples, snakemake.input.peaks))

rows = []
for sample in samples:
    fs = flagstat(flagstats[sample])
    md = markdup_stats(markdups[sample])
    reads_in = int(fs["primary"])
    aligned = int(fs["primary mapped"])
    row = {
        "sample": sample,
        "reads_in": reads_in,
        "reads_aligned": aligned,
        "pct_aligned": round(100 * aligned / reads_in, 2) if reads_in else 0.0,
        ## markdup -r: what it wrote is what is left after every filter
        "reads_filtered": md["WRITTEN"],
        "duplicate_rate": round(md["DUPLICATE TOTAL"] / md["EXAMINED"], 4) if md["EXAMINED"] else 0.0,
        "peaks": pd.NA,
        "frip": pd.NA,
    }
    if sample in peak_samples:
        with open(peak_files[sample]) as fh:
            row["peaks"] = sum(1 for _ in fh)
        row["frip"] = pd.read_csv(frips[sample], sep="\t")["frip"].iloc[0]
    rows.append(row)

pd.DataFrame(rows).to_csv(snakemake.output.tsv, sep="\t", index=False, na_rep="NA")
print(f"QC table for {len(rows)} samples written", file=sys.stderr)
