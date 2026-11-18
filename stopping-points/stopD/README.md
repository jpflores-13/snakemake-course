# RegPipe: the course pipeline

RegPipe takes single-end ChIP-seq and DNase-seq reads to filtered BAMs, peaks,
signal tracks, a QC table and a figure of one locus. It is the pipeline the
Snakemake course builds step by step, and it follows the same layout as the
lab's MicroCPipe, TTpipe and ChromSimPipe: a launcher script, a samplesheet, a
config file, profiles per compute site, rule files, conda envs and tests.

The course data (in `../data`) are reads from HCT116 cells (CTCF, H3K27ac,
their inputs, DNase-seq) in the 5 Mb window chr8:125,000,000-130,000,000
around *MYC*, plus processed TT-seq tracks and enhancer annotations from GEO.

## Quick start

You need `python3` >= 3.11 and `conda` >= 24.7.1 (a one-time
[Miniforge](https://github.com/conda-forge/miniforge) install in
`$HOME/miniforge3`). Everything else is installed by Snakemake into one conda
environment per group of rules (`envs/`) the first time it is needed.

```bash
cd course-pipeline
bash RegPipe.sh -n      # dry run: lists every job, runs nothing
bash RegPipe.sh         # run on this machine (profiles/local)
```

Run every command from this folder (the one that holds `RegPipe.sh`). Paths in
the config and samplesheet are relative to it: `dataDir: '../data'` points at
the course data, and results go to `output/`.

On a SLURM cluster, edit `profiles/longleaf/config.yaml` (or copy
`profiles/slurm-template/`), then:

```bash
export REGPIPE_PROFILE=profiles/longleaf
sbatch RegPipe.sh
```

If a run is interrupted and Snakemake says the directory is locked:
`bash unlock.sh`, then start again.

## What it does

| Rule | Does | Jobs on the course data |
|---|---|---|
| `fastqc` | FastQC on each raw FASTQ | one per sample |
| `bowtie2_index` | index the reference (a `directory()` output) | 1 |
| `align` | `bowtie2 \| samtools sort` to a temporary BAM | one per sample |
| `filter` | MAPQ and flag filter, drop blacklisted reads, `samtools markdup -r`, index | one per sample |
| `call_peaks` | MACS3; ChIP samples use their `Control`, DNase has none | one per non-control sample |
| `consensus_peaks` | peaks found in every replicate of a target | one per target |
| `bigwig` | deepTools `bamCoverage`, CPM, course window only | one per sample |
| `frip` | fraction of reads in peaks (Python `script:`) | one per non-control sample |
| `qc_table` | one TSV across samples | 1 |
| `ctcf_rad21_overlap` | CTCF consensus peaks vs ENCODE RAD21 and CTCF peaks | 1 |
| `locus_plot` | plotgardener figure of the window (R `script:`) | 1 (switch `make_locus_plot`) |
| `enhancer_activity` | TT-seq signal over published enhancers / eRNAs, with peak overlaps (R `script:`) | 1 (switch `ttseq: enabled:`) |

With `scatter_chunks: N` (module 7), `align` is replaced by `split_fastq`,
`align_chunk` (N per sample) and `merge_chunks`. The filtered BAMs keep the
same reads at the same positions.

## What do I edit?

**The samplesheet** (`RegSamplesheet.txt`, tab-separated, one row per FASTQ):
`Project Cell_Type Assay Target Bio_Rep Control Read1 Sequencing_Directory`.
Sample names are the `fileNamesFrom` columns joined with `_`
(`HCT116_CTCF_1`). `Control` holds the name of the control sample, or `NA`.
A sample that another sample names as its control gets no peaks.
`Sequencing_Directory` is relative to `dataDir` unless it is absolute.

**The config** (`config/RegConfig.yaml`). Every key has a comment. The ones you
change most:

| Key | Default | Meaning |
|---|---|---|
| `samplesheet` | `RegSamplesheet.txt` | the samplesheet |
| `fileNamesFrom` | `['Cell_Type', 'Target', 'Bio_Rep']` | columns that make sample names |
| `dataDir` | `../data` | where relative data paths are read from |
| `outputDir` | `output` | where results go (under `$REGPIPE_OUTPUT_ROOT` if set) |
| `reference: fasta / blacklist` | course files | genome FASTA and blacklist BED |
| `window` | chr8:125,000,000-130,000,000 | region for bigWigs and the figure |
| `effectiveGenomeSize` | 5000001 | MACS3 `-g` (bases reads can map to) |
| `minMapq`, `excludeFlags` | 30, 1804 | read filter |
| `scatter_chunks` | 0 | split each FASTQ into N chunks (0 = off) |
| `macs3: targetArgs` | per target | extra MACS3 arguments for each Target |
| `bigwig` | bin 10, CPM, extend 200 | bamCoverage settings |
| `encodePeaks`, `overlapTarget` | RAD21, CTCF peaks; CTCF | reference peaks to compare with |
| `make_locus_plot`, `locusPlot` | on; MYC, CTCF/H3K27ac/DNase | the figure |
| `ttseq` | on; 2 replicates x 2 strands, enhancers, eRNAs | TT-seq tracks and `enhancer_activity` |
| `notify` | off | email on start, success, error |

**The profile** (`profiles/<site>/config.yaml`) holds threads, memory and run
time for every rule (`set-threads`, `set-resources`). The rules themselves only
carry a default `threads:`.

## Outputs

```text
output/
├── <sample>/
│   ├── fastqc/<sample>_fastqc.html
│   ├── <sample>_filtered.bam (+ .bai)
│   ├── <sample>_aligned_flagstat.tsv    # reads in / aligned
│   ├── <sample>_markdup.txt             # duplicate statistics
│   └── <sample>_frip.tsv
├── reference/bowtie2_index/
├── peaks/<sample>_peaks.narrowPeak      # + .xls, _summits.bed
├── consensus/<target>_consensus.bed
├── tracks/<sample>.bw
├── qc/qc_table.tsv
├── qc/ctcf_rad21_overlap.tsv
├── qc/enhancer_activity.tsv
├── figures/MYC_locus.pdf
├── logs/<rule>/...
└── benchmarks/<rule>/...
```

## Tests

```bash
python -m pytest tests/
```

The tests dry-run the workflow on the course data and check the number of jobs
per rule against numbers worked out from the samplesheet, with and without
`scatter_chunks`.

## Apple silicon

bioconda has no Apple-silicon (osx-arm64) build of `bioconductor-plotgardener`,
so `envs/regpipe_r.yml` does not solve there. The other three envs do. Either
set `make_locus_plot: false` and `ttseq: enabled: false`, or build the R env
for Intel Macs, which runs under Rosetta 2: `export CONDA_SUBDIR=osx-64`
before the first run (it then applies to every env Snakemake builds; delete
`.snakemake/conda` first if envs were already built natively).

## Gene track without internet on the compute node

`envs/regpipe_r.yml` includes `TxDb.Hsapiens.UCSC.hg38.knownGene` and
`org.Hs.eg.db`. These bioconda packages download their data from
bioconductor.org while the env is built, so building the env fails on a
machine that cannot reach that site (micromamba, unlike conda, prints the
download error and carries on, leaving an env without the two packages).
Either build the env once on a machine with internet (`bash RegPipe.sh
--conda-create-envs-only`), or delete those two lines from the env file and set
`locusPlot: genesGtf:` to a GTF of gene models (for example UCSC's
`hg38.ncbiRefSeq.gtf.gz`): the gene track is then built from the GTF.
