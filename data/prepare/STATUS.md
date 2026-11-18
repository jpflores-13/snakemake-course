# Data status: ready

Built 2026-11-18 by running `prepare/Snakefile` (Snakemake 8.27.1) to
completion. All outputs verified: every `.gz` passes `gunzip -t`, read
counts below are lines/4 of each FASTQ (also in `data/manifest.tsv`), the
reference is one sequence `chr8` (145,138,636 bp) with 0 non-N bases outside
chr8:125,000,000-130,000,000 and 0 N inside it, and `bowtie2-build --threads 4`
on it completes in 6.4 s (index deleted afterwards).

| Sample | Reads | Read length |
|---|---|---|
| HCT116_CTCF_1 | 28,634 | 50 |
| HCT116_CTCF_2 | 57,056 | 50 |
| HCT116_input-CTCF_1 | 97,020 | 50 |
| HCT116_input-CTCF_2 | 109,347 | 50 |
| HCT116_H3K27ac_1 | 169,920 | 36 |
| HCT116_H3K27ac_2 | 210,899 | 36 |
| HCT116_input-H3K27ac_1 | 92,678 | 36 |
| HCT116_input-H3K27ac_2 | 183,061 | 36 |
| HCT116_DNase_1 | 115,516 | 36 |
| HCT116_DNase_2 | 132,370 | 36 |

Other files:

- `data/samplesheet.txt` (10 samples; ChIP rep n uses control rep n)
- `data/reference/chr8_course.fa.gz` (bgzip), `data/reference/blacklist.bed.gz`
- `data/peaks/RAD21_ENCFF391AAM.bed.gz` (144 peaks in window),
  `data/peaks/CTCF_ENCODE_IDR.bed.gz` (50 peaks, ENCFF958TMV)
- `data/geo/TTseq_HCT116_{1,2}_{plus,minus}.bw`, `data/geo/TTseq_HCT116_enhancers.gtf.gz`
  (118 regions), `data/geo/TTseq_HCT116_eRNAs.gtf.gz` (141 eRNAs), all GSE152291, GRCh38
- `data/manifest.tsv`, `data/README.md`

Not included: GSE121355 (MED26) HCT116 tracks, because they are hg19.

Shipped size of `data/` (without `prepare/work/` and `.snakemake/`): about 47 MB.
