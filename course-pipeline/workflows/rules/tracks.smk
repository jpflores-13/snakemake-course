## Tracks: bigwig (deepTools, per sample) and locus_plot (R / plotgardener, once).


## CPM-normalized coverage, only for the course window (--region), so the files stay small.
rule bigwig:
    input:
        bam = lambda wildcards: filtered_bam(wildcards.sample),
    output:
        bw = OUT + "/tracks/{sample}.bw",
    log:
        LOGS + "/bigwig/{sample}.log",
    benchmark:
        BENCH + "/bigwig/{sample}.tsv",
    threads: 2
    conda: ENVS + "/regpipe_tracks.yml"
    params:
        region = DEEPTOOLS_REGION,
        bin_size = config["bigwig"]["binSize"],
        norm = config["bigwig"]["normalizeUsing"],
        extend_reads = config["bigwig"]["extendReads"],
    shell:
        """
        bamCoverage -b {input.bam} -o {output.bw} -p {threads} \
            --region {params.region} --binSize {params.bin_size} \
            --normalizeUsing {params.norm} --extendReads {params.extend_reads} > {log} 2>&1
        """


## One PDF of the window: signal for every sample of the chosen targets, their consensus
## peaks, the ENCODE RAD21 peaks and the genes. The R script reads everything from the
## `snakemake` object (snakemake@input, snakemake@params, ...), so it has no arguments.
if MAKE_LOCUS_PLOT:

    PLOT_TARGETS = config["locusPlot"]["targets"]
    PLOT_SAMPLES = [s for t in PLOT_TARGETS for s in SAMPLES_BY_TARGET[t]]

    rule locus_plot:
        input:
            bigwigs = [bigwig_file(s) for s in PLOT_SAMPLES],
            consensus = [consensus_file(t) for t in PLOT_TARGETS],
            rad21 = data_path(config["encodePeaks"]["rad21"]),
        output:
            pdf = LOCUS_PLOT,
        log:
            LOGS + "/locus_plot/locus_plot.log",
        benchmark:
            BENCH + "/locus_plot/locus_plot.tsv",
        threads: 1
        conda: ENVS + "/regpipe_r.yml"
        params:
            samples = PLOT_SAMPLES,
            sample_targets = [SAMPLE_TABLE.loc[s, "Target"] for s in PLOT_SAMPLES],
            targets = PLOT_TARGETS,
            chrom = WINDOW["chrom"],
            start = WINDOW["start"],
            end = WINDOW["end"],
            assembly = config["locusPlot"]["assembly"],
            title = config["locusPlot"]["name"],
        script:
            SCRIPTS + "/locus_plot.R"
