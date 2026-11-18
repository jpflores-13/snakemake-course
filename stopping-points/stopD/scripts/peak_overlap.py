"""Overlap of the CTCF consensus peaks with ENCODE reference peaks (rule ctcf_rad21_overlap).

Run by Snakemake's `script:` directive. For each reference named in
snakemake.params.references (each is also a named input), one output row:
  consensus_peaks            our consensus peaks
  consensus_overlapping      ... of them overlapping at least one reference peak
  fraction_consensus         the ratio of the two
  reference_peaks_in_window  reference peaks inside the course window
  reference_recovered        ... of them overlapping at least one consensus peak
  fraction_reference         the ratio of the two
Two peaks overlap when they share at least 1 bp. BED coordinates are 0-based, end-exclusive.
"""
import gzip
import sys

sys.stderr = open(snakemake.log[0], "w")


def read_bed(path):
    """(chrom, start, end) of every line of a BED file, gzipped or not."""
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt") as fh:
        return [(f[0], int(f[1]), int(f[2])) for f in (line.split("\t") for line in fh)
                if len(f) >= 3 and not f[0].startswith(("#", "track", "browser"))]


def overlaps_any(peak, others):
    """True if `peak` shares at least 1 bp with any interval in `others`."""
    chrom, start, end = peak
    return any(c == chrom and s < end and start < e for c, s, e in others)


consensus = read_bed(snakemake.input.consensus)
chrom, start, end = snakemake.params.chrom, snakemake.params.start - 1, snakemake.params.end

with open(snakemake.output.tsv, "w") as out:
    out.write("reference\tconsensus_peaks\tconsensus_overlapping\tfraction_consensus\t"
              "reference_peaks_in_window\treference_recovered\tfraction_reference\n")
    for name in snakemake.params.references:
        reference = [p for p in read_bed(snakemake.input[name])
                     if p[0] == chrom and p[1] < end and start < p[2]]   # only peaks in the window
        hit = sum(overlaps_any(p, reference) for p in consensus)
        found = sum(overlaps_any(p, consensus) for p in reference)
        frac_c = hit / len(consensus) if consensus else 0.0
        frac_r = found / len(reference) if reference else 0.0
        out.write(f"{name}\t{len(consensus)}\t{hit}\t{frac_c:.3f}\t{len(reference)}\t{found}\t{frac_r:.3f}\n")
        print(f"{name}: {hit}/{len(consensus)} consensus peaks overlap; "
              f"{found}/{len(reference)} reference peaks in the window recovered", file=sys.stderr)
