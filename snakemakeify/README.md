# snakemakeify/

Legacy analysis scripts for the Snakemake-ify exercises
(`exercises/snakemakeify.qmd`). They are the kind of scripts a lab writes
before it uses a workflow manager: they work, they run on the real course data
(HCT116 CTCF and H3K27ac ChIP-seq, DNase-seq and TT-seq, chr8:125-130 Mb), and each has
habits that Snakemake replaces. Your job is to turn them into rules.

Do not fix them here. They are meant to stay the way they are.

| Script | What it does | Writes (in the current folder) | Main thing to convert |
|---|---|---|---|
| `01_fastqc.sh` | FastQC on every raw FASTQ | `fastqc/<sample>_fastqc.{html,zip}` | for-loop and skip check become a `{sample}` wildcard and `expand()` |
| `02_align.sh` | unzips the reference, builds the bowtie2 index once, aligns and sorts every sample | `chr8_course.fa(.fai)`, `chr8_course.*.bt2`, `<sample>.bam(.bai)`, `<sample>.bowtie2.log` | a one-off step as its own rule with `multiext()`; `threads:`; a pipe that hides failures |
| `03_filter.sh` | MAPQ filter, blacklist removal, duplicate removal, flagstat, CPM bigWig | `<sample>.filt.bam(.bai)`, `<sample>.flagstat.txt`, `<sample>.markdup.log`, `tracks/<sample>.bw` | one script with many outputs becomes several rules; `rm` becomes `temp()`; settings become `params:` from config |
| `04_call_peaks.sh` | MACS3 per sample; ChIP with its control from the samplesheet, DNase without one | `peaks/<sample>_peaks.narrowPeak`, `_summits.bed`, `_peaks.xls` | looking up the control by name becomes an input function |
| `05_qvalue_sweep.sh` | re-calls CTCF peaks at four q-value cutoffs and counts them | `sweep/<sample>_q<q>_peaks.narrowPeak`, `sweep/sweep_counts.tsv` | a parameter loop becomes a wildcard; a summary becomes an aggregating rule |
| `06_qc_summary.py` | reads, peaks and FRiP for every sample, in one table | `qc_summary.tsv` | `glob()` becomes explicit inputs; the script reads `snakemake.input` |
| `07_overlap.sh` | replicate-consensus peaks per target, CTCF peaks with RAD21, CTCF summit windows | `overlap/*.bed`, `overlap/counts.txt` | a per-target wildcard; a hidden dependency on `chr8_course.fa.fai`; an empty file left behind by a failed command |
| `08_locus_plot.R` | MYC locus figure from the bigWigs and consensus peaks (GenomicRanges, rtracklayer) | `MYC_locus.pdf`, `MYC_locus_CTCF_peaks.tsv` | hard-coded file names become `snakemake@input`, `@params`, `@output` |
| `09_ttseq_enhancers.R` | mean TT-seq signal on each strand over the published HCT116 enhancers (GEO GSE152291), per replicate | `ttseq_enhancers_rep{1,2}.tsv`, `ttseq_enhancers_all.tsv` | two nested loops (replicate, strand) become two wildcards; one R script becomes a per-file step plus a combining step |
| `run_all.sh` | runs 01 to 09 in order | everything above | the whole thing becomes one Snakefile with `rule all` |

## Running the legacy version

You need the course environment (`envs/course.yml`), which has samtools,
bowtie2, MACS3, bedtools, deepTools, FastQC and R with GenomicRanges and
rtracklayer.

Every script has the data folder at the top:

```bash
DATA=~/snakemake-course/data
```

(`08_locus_plot.R` has the same path in `rad21_file`, and `09_ttseq_enhancers.R`
in `geo`). If your copy of
the course is somewhere else, edit those lines. Then run from an empty folder,
because every script writes into the folder you run it from:

```bash
mkdir -p ~/snakemakeify/legacy && cd ~/snakemakeify/legacy
bash ~/snakemake-course/snakemakeify/run_all.sh 2>&1 | tee run_all.log
```

The order matters: 02 needs nothing, 03 needs 02's BAMs, 04 and 05 need 03's
filtered BAMs, 06 needs 03 and 04, 07 needs 04 (and 02's `.fai`), 08 needs
03 and 07, 09 needs only the files in `data/geo/`. `run_all.sh` does not stop
when a step fails.

The whole run takes about a minute and a half on a 4-core machine. Running it
again takes about 20 seconds, because 06, 08 and 09 have no skip check and
always run.

To run one step, `cd` into the same folder and run that script, for example
`bash ~/snakemake-course/snakemakeify/04_call_peaks.sh`.

Keep this folder. The exercises compare your Snakemake outputs with these.
