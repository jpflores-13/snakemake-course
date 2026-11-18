# Exercise 8: 08_locus_plot.R
rule locus_plot:
    input:
        bigwigs=expand("results/tracks/{sample}.bw", sample=PEAK_SAMPLES),
        consensus=expand("results/overlap/{target}_consensus.bed", target=TARGETS),
        rad21=f"{DATA}/peaks/RAD21_ENCFF391AAM.bed.gz",
    output:
        pdf="results/figures/MYC_locus.pdf",
        tsv="results/figures/MYC_locus_CTCF_peaks.tsv",
    params:
        track_names=PEAK_SAMPLES,
        peak_names=TARGETS,
        chrom=config["locus"]["chrom"],
        start=config["locus"]["start"],
        end=config["locus"]["end"],
    log:
        "results/logs/locus_plot.log",
    script:
        "../scripts/locus_plot.R"
