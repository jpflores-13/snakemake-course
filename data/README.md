# Course data

Everything in this folder is real, public data. Nothing here is simulated.
The files are small cuts of public ENCODE, UCSC and GEO files, made by the
workflow in `prepare/`. This page says where each file came from and how to
make it again.

The dataset selection follows the public data cited in the HCT116
Mediator/cohesin preprint, bioRxiv doi
[10.64898/2026.11.10.765568](https://doi.org/10.64898/2026.11.10.765568).

## The window

All data cover one region of hg38 (GRCh38):

```
chr8:125,000,000-130,000,000
```

That is 1-based and inclusive, the way `samtools` and genome browsers write
regions. In BED (0-based, half-open) it is `chr8  124999999  130000000`.

Why this region: it holds the *MYC* gene (chr8:127.73 Mb) and the gene
desert upstream of it, where the colorectal cancer risk enhancers sit
(including the rs6983267 enhancer about 335 kb upstream of *MYC*). HCT116 is a
colorectal cancer line, so CTCF, H3K27ac and DNase signal at these enhancers
is the biology the course pipeline looks at. Five megabases is big enough to
call real peaks and small enough that every step runs in seconds on a laptop.

## What is here

```
data/
├── samplesheet.txt          # input for the course pipeline
├── manifest.tsv             # one row per file: source, checksums, read counts
├── fastq/                   # single-end reads from the window, one file per sample
├── reference/
│   ├── chr8_course.fa.gz    # hg38 chr8, N outside the window
│   └── blacklist.bed.gz     # ENCODE GRCh38 exclusion list (whole file)
├── peaks/
│   ├── RAD21_ENCFF391AAM.bed.gz   # ENCODE RAD21 IDR peaks, window only
│   └── CTCF_ENCODE_IDR.bed.gz     # ENCODE's own CTCF peaks, window only
├── geo/                     # optional extras from GEO (TT-seq, HCT116)
└── prepare/                 # the workflow that made all of the above
```

### Reads (`fastq/`)

| Sample | Assay | ENCODE experiment | ENCODE file (GRCh38 unfiltered alignments) | Read length |
|---|---|---|---|---|
| HCT116_CTCF_1 | ChIP-seq | ENCSR000BSE | ENCFF321CBF | 50 |
| HCT116_CTCF_2 | ChIP-seq | ENCSR000BSE | ENCFF679GVY | 50 |
| HCT116_input-CTCF_1 | ChIP-seq control | ENCSR000BVT | ENCFF761OIH | 50 |
| HCT116_input-CTCF_2 | ChIP-seq control | ENCSR000BVT | ENCFF264PNB | 50 |
| HCT116_H3K27ac_1 | ChIP-seq | ENCSR661KMA | ENCFF943GHK | 36 |
| HCT116_H3K27ac_2 | ChIP-seq | ENCSR661KMA | ENCFF168GLY | 36 |
| HCT116_input-H3K27ac_1 | ChIP-seq control | ENCSR198WIH | ENCFF167GNJ | 36 |
| HCT116_input-H3K27ac_2 | ChIP-seq control | ENCSR198WIH | ENCFF057BHM | 36 |
| HCT116_DNase_1 | DNase-seq | ENCSR000ENM | ENCFF166PCV | 36 |
| HCT116_DNase_2 | DNase-seq | ENCSR000ENM | ENCFF619LVU | 36 |

Read counts per file are in `manifest.tsv` (column `read_count`). As a
check, aligning `HCT116_CTCF_1` and `HCT116_DNase_1` back to
`chr8_course.fa.gz` with bowtie2 defaults gave 99.99% and 99.77% overall
alignment.

How each FASTQ was made:

1. Download the GRCh38 **unfiltered alignments** BAM of one biological
   replicate from the experiment's ENCODE default analysis, and check its md5
   against the ENCODE metadata.
2. Keep the alignments that overlap the window. The ChIP-seq BAMs are
   sorted by position, so they are indexed and queried by region
   (`samtools view -F 0x980 bam chr8:125000000-130000000`). ENCODE's DNase-seq
   BAMs are sorted by read name and cannot be indexed, so they are read from
   start to end and filtered with the same window as a BED file
   (`samtools view -F 0x980 -L window.bed bam`). Both give every alignment that
   overlaps the window. `-F 0x980` drops
   secondary and supplementary records, so each read appears once, and drops
   read 2. All ten BAMs are single-end, so in practice no reads are lost to
   that rule; it only matters if a paired-end BAM is ever added.
3. Write the reads back to FASTQ with `samtools fastq -n` and compress with
   `bgzip`. `samtools fastq` reverse-complements reads that aligned to the
   minus strand, so the sequences and qualities are the reads as sequenced.

"Unfiltered" matters: these BAMs still have PCR duplicates, multimapping
reads and low-MAPQ reads. That is on purpose. The course pipeline filters on
MAPQ, removes blacklisted regions and marks duplicates itself, and you can see
each step remove reads.

Things to know about these reads:

- ChIP-seq reads are in coordinate order and DNase-seq reads in read-name
  order, because that is how the source BAMs were sorted. Aligners do not care.
- A read was kept if its ENCODE alignment overlapped the window, so a few reads
  at the edges hang over into the masked part of the reference. They align with
  a lower score or not at all. This touches only the outer read length of each
  end of a 5 Mb window.
- ENCODE's ChIP-seq pipeline crops reads to a fixed length before alignment
  (the header of ENCFF321CBF shows a `crop_50` step), so read lengths are the
  mapped lengths in the table above, which may be shorter than sequenced.

### Samplesheet (`samplesheet.txt`)

Tab-separated, one row per FASTQ, with the columns the course pipeline expects:
`Project Cell_Type Assay Target Bio_Rep Control Read1 Sequencing_Directory`.

- `Cell_Type`, `Target` and `Bio_Rep` come from ENCODE. Sample names are
  built from them as `{Cell_Type}_{Target}_{Bio_Rep}`.
- Control samples get the target `input-<ChIP target>` (for example
  `input-CTCF`), so their names do not clash.
- `Control` names the control sample for each ChIP-seq sample. The rule: ChIP
  replicate *n* uses control replicate *n* if the control experiment has one,
  otherwise control replicate 1. Both control experiments here have replicates
  1 and 2, so each ChIP replicate gets the control with the same number.
  Controls themselves and DNase-seq have `NA`.
- `Sequencing_Directory` is `data/fastq/`, relative to the course root.

### Reference (`reference/`)

`chr8_course.fa.gz` is hg38 chr8 from UCSC
(<https://hgdownload.soe.ucsc.edu/goldenPath/hg38/chromosomes/chr8.fa.gz>,
md5 checked against UCSC's `md5sum.txt`). Every base outside the window is
replaced with `N`. The sequence keeps the name `chr8` and its full length
(145,138,636 bp), so positions in your BAMs and peak files are real hg38
coordinates and line up with ENCODE, UCSC and GEO files. Inside the window
the bases are exactly as UCSC wrote them, including lowercase soft-masked
repeats. The file is bgzip-compressed, so `samtools faidx` works on it.

Building the bowtie2 index of this file took 6.4 seconds with
`bowtie2-build --threads 4` (bowtie2 2.5.5, 4-core Linux machine), because
the runs of `N` are skipped. The index is about 15 MB. It is not shipped:
building it is part of the course pipeline.

`blacklist.bed.gz` is the ENCODE GRCh38 exclusion list ENCFF356LFX
(annotation ENCSR636HFF), copied unchanged, all chromosomes.

### Peaks (`peaks/`)

Both files keep only peaks that lie completely inside the window, sorted by
start; the lines themselves are unchanged (narrowPeak format).

- `RAD21_ENCFF391AAM.bed.gz`: ENCODE IDR thresholded peaks for RAD21 in HCT116
  (experiment ENCSR000BSB). The course pipeline overlaps your CTCF peaks
  with these.
- `CTCF_ENCODE_IDR.bed.gz`: ENCODE's own CTCF peaks for ENCSR000BSE, the
  "conservative IDR thresholded peaks" of the default GRCh38 analysis
  (ENCFF958TMV, analysis ENCAN900DLY). Use it to compare your peak calls with
  ENCODE's.

### GEO extras (`geo/`)

From GSE152291 (TT-seq in 14 cancer cell lines, Lidschreiber et al., PMID
33502116), HCT116 only, GRCh38 as deposited:

- `TTseq_HCT116_{1,2}_{plus,minus}.bw`: strand-specific TT-seq coverage
  (size-factor normalized, as deposited) for replicates 1 and 2 (GSM4610670,
  GSM4610671), cut to the window. Values are unchanged; intervals crossing the
  window edge are clipped to it. The header keeps chr8 at full length.
- `TTseq_HCT116_enhancers.gtf.gz` and `TTseq_HCT116_eRNAs.gtf.gz`: the
  authors' transcribed enhancer and eRNA annotations for HCT116 (from
  `GSE152291_enhancer.gtf.tar.gz` and `GSE152291_eRNAs.gtf.tar.gz`), window
  only.

What else exists in these two GEO series, and why it is not here:

- GSE152291 also has the same bigWigs for 13 other cell lines, a raw tar
  (16 GB), and "conservative" subsets of the enhancer and eRNA annotations.
  The course only uses HCT116.
- GSE121355 (PMID 31402173) has HCT116 MED26, RAD21,
  Pol II and input ChIP-seq bigWigs (Rad21 degron, untreated and auxin or
  amanitin treated), HCT116 Hi-C `.hic` files and promoter capture Hi-C calls,
  plus many mouse CH12 files. Its HCT116 tracks are aligned to **hg19**, not
  hg38. Moving them to hg38 would need liftOver, which changes the data, so we
  left them out. There are no processed peak files for HCT116.

## Provenance and checksums

`manifest.tsv` has one row per file in this folder (except this README and the
workflow): the path, the ENCODE experiment and analysis or GEO accession, the
ENCODE file accession, the download URL, the md5 of the source file, where
that md5 came from (ENCODE metadata, UCSC `md5sum.txt`, or computed on
download for GEO, which publishes none), the md5 and size of the file shipped
here, and the read count for FASTQs.

## How the files were chosen

The workflow does not hard-code ENCODE file accessions for reads or for the
CTCF peaks. For each experiment in `prepare/config.yaml` it reads the
experiment JSON from the ENCODE REST API
(`https://www.encodeproject.org/experiments/<accession>/?format=json`) and:

1. Takes the experiment's `default_analysis`. If an experiment had none, it
   would take the released GRCh38 analysis from the newest ENCODE phase
   (ENCODE4 before ENCODE3), and stop with an error if that is still
   ambiguous. You can pin an analysis in the config with `analysis: ENCAN...`.
   All five experiments here have a default analysis, all ENCODE4 GRCh38.
2. In that analysis, takes the released GRCh38 BAM with output type
   "unfiltered alignments" for each biological replicate (exactly one per
   replicate, or it stops).
3. Follows `possible_controls` to the control experiments (ENCSR000BSE uses
   ENCSR000BVT, ENCSR661KMA uses ENCSR198WIH; the DNase-seq experiment
   ENCSR000ENM has none) and repeats steps 1 and 2 for them.

Files download from the `@@download` links, which redirect to the
`encode-public` S3 bucket. The JSON the workflow saw is cached in
`prepare/work/metadata/`, so a rerun uses the same choices. Delete that folder
to pick up changes on the ENCODE portal.

## Making the files again

Only the maintainer needs to do this. From the course root:

```bash
snakemake -s data/prepare/Snakefile --cores 4 --use-conda
```

or, with the tools already installed (this is how the shipped files were
made, in a micromamba environment with samtools 1.24, htslib 1.24 and
pyBigWig 0.3.30, the same versions as `prepare/envs/prepare.yml`):

```bash
export PATH=/opt/mamba/envs/tools/bin:$PATH
snakemake -s data/prepare/Snakefile --cores 4
```

The workflow uses Snakemake 8.27.1. It downloads about 18 GB of BAMs, at most
two at a time (`--resources download=N` changes that), into
`prepare/work/`, and deletes each BAM once its reads are extracted. Peak
disk use stays under about 6 GB. `prepare/work/` and `.snakemake/` are
gitignored.

If Snakemake 8.27.1 fails after a job with "Error running conda info", the
`conda` command is missing from `PATH`. Snakemake asks conda for a checksum of
any rule with a `conda:` directive, even without `--use-conda`. Put any conda
on `PATH` (we used one installed with micromamba) and run again.

## License and citation

ENCODE data are freely available with no restrictions on use; see
<https://www.encodeproject.org/help/citing-encode/>. If you use these files,
cite the ENCODE Project Consortium and the ENCODE experiments listed above.
UCSC hg38 sequence is from the Genome Reference Consortium via the UCSC Genome
Browser. The GEO files belong to their submitters: cite GSE152291 (Lidschreiber
et al., 2021) if you use `geo/`.

The selection of datasets comes from the preprint at bioRxiv doi
10.64898/2026.11.10.765568.
