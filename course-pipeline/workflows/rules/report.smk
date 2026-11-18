## QC and summaries: frip (per sample), qc_table, ctcf_rad21_overlap and
## enhancer_activity (once).


## Fraction of reads in peaks. A Python script run with `script:`: inside it, the
## `snakemake` object holds this rule's input, output, log and wildcards.
rule frip:
    input:
        bam = lambda wildcards: filtered_bam(wildcards.sample),
        bai = lambda wildcards: filtered_bam(wildcards.sample) + ".bai",
        peaks = lambda wildcards: peak_file(wildcards.sample),
    output:
        tsv = OUT + "/{sample}/{sample}_frip.tsv",
    log:
        LOGS + "/frip/{sample}.log",
    benchmark:
        BENCH + "/frip/{sample}.tsv",
    threads: 1
    conda: ENVS + "/regpipe_peaks.yml"
    script:
        SCRIPTS + "/frip.py"


## One row per sample: reads in, aligned, kept after filtering, duplicate rate, peaks, FRiP.
## Controls have no peaks, so their peak and FRiP columns are NA.
rule qc_table:
    input:
        flagstat = expand(OUT + "/{sample}/{sample}_aligned_flagstat.tsv", sample=SAMPLES),
        markdup = expand(OUT + "/{sample}/{sample}_markdup.txt", sample=SAMPLES),
        frip = expand(OUT + "/{sample}/{sample}_frip.tsv", sample=PEAK_SAMPLES),
        peaks = [peak_file(s) for s in PEAK_SAMPLES],
    output:
        tsv = OUT + "/qc/qc_table.tsv",
    log:
        LOGS + "/qc_table/qc_table.log",
    benchmark:
        BENCH + "/qc_table/qc_table.tsv",
    threads: 1
    conda: ENVS + "/regpipe_peaks.yml"
    params:
        samples = SAMPLES,
        peak_samples = PEAK_SAMPLES,
    script:
        SCRIPTS + "/qc_table.py"


## How many of our CTCF consensus peaks overlap ENCODE's RAD21 peaks (cohesin sits at
## CTCF sites) and ENCODE's own CTCF peaks, and how many of the ENCODE peaks in the
## window we found. Two peaks overlap when they share at least 1 bp.
rule ctcf_rad21_overlap:
    input:
        consensus = consensus_file(OVERLAP_TARGET),
        RAD21_ENCODE = data_path(config["encodePeaks"]["rad21"]),
        CTCF_ENCODE = data_path(config["encodePeaks"]["ctcf"]),
    output:
        tsv = OUT + "/qc/ctcf_rad21_overlap.tsv",
    log:
        LOGS + "/ctcf_rad21_overlap/ctcf_rad21_overlap.log",
    benchmark:
        BENCH + "/ctcf_rad21_overlap/ctcf_rad21_overlap.tsv",
    threads: 1
    conda: ENVS + "/regpipe_peaks.yml"
    params:
        references = ["RAD21_ENCODE", "CTCF_ENCODE"],   # names of the inputs above
        chrom = WINDOW["chrom"],
        start = WINDOW["start"],
        end = WINDOW["end"],
    script:
        SCRIPTS + "/peak_overlap.py"


## TT-seq signal (newly made RNA, per replicate and strand) over the published enhancers
## and eRNAs, and which of them overlap our consensus peaks and the ENCODE RAD21 peaks.
## An R script run with `script:`; switched on and off with ttseq: enabled:.
if TTSEQ_ENABLED:

    rule enhancer_activity:
        input:
            ttseq = [t["path"] for t in TTSEQ_TRACKS],
            annotations = list(TTSEQ_ANNOTATIONS.values()),
            consensus = [consensus_file(t) for t in TTSEQ["overlapTargets"]],
            rad21 = data_path(config["encodePeaks"]["rad21"]),
        output:
            tsv = OUT + "/qc/enhancer_activity.tsv",
        log:
            LOGS + "/enhancer_activity/enhancer_activity.log",
        benchmark:
            BENCH + "/enhancer_activity/enhancer_activity.tsv",
        threads: 1
        conda: ENVS + "/regpipe_r.yml"
        params:
            ## names in the same order as the input lists above
            ttseq_tracks = [t["track"] for t in TTSEQ_TRACKS],
            annotation_names = list(TTSEQ_ANNOTATIONS),
            overlap_targets = TTSEQ["overlapTargets"],
            chrom = WINDOW["chrom"],
            start = WINDOW["start"],
            end = WINDOW["end"],
        script:
            SCRIPTS + "/enhancer_activity.R"
