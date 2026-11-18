## RegPipe: ChIP-seq and DNase-seq from FASTQ to peaks, tracks, QC and a locus figure.
##
## Per sample:  fastqc; align (bowtie2 | samtools sort); filter (MAPQ, blacklist,
##              duplicates); bigwig; and, for samples that are not controls,
##              call_peaks (MACS3, with the sample's control) and frip.
## Per target:  consensus_peaks (peaks found in every replicate).
## Once:        bowtie2_index, qc_table, ctcf_rad21_overlap, locus_plot.
##
## Samples come from the samplesheet, settings from config/RegConfig.yaml.
## The rules are in workflows/rules/; this file only wires them together.
## Run it with RegPipe.sh (see README.md), from the folder that holds RegPipe.sh.

import os

configfile: "config/RegConfig.yaml"

include: "rules/common.smk"

RUN_NAME = "RegPipe " + os.path.splitext(os.path.basename(config["samplesheet"]))[0]

onstart:
    notify("start", f"Started. Samples: {', '.join(SAMPLES)}.", RUN_NAME)

onsuccess:
    print("RegPipe completed successfully!")
    notify("success", f"Finished successfully.\nResults: {OUT}\nQC table: {OUT}/qc/qc_table.tsv", RUN_NAME)

onerror:
    print(f"RegPipe failed. Per-job logs are in {LOGS}/<rule>/; the Snakemake log is {log}")
    notify("error", f"A job failed. Per-job logs: {LOGS}/<rule>/\nSnakemake log: {log}", RUN_NAME)

rule all:
    input:
        all_targets(),

include: "rules/align.smk"
include: "rules/peaks.smk"
include: "rules/tracks.smk"
include: "rules/report.smk"
