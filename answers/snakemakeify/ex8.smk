# Exercise 8 solution: 08_locus_plot.R
# Run from your working folder (the one with the data/ link in it):
#   snakemake -s path/to/answers/snakemakeify/ex8.smk -c 4
configfile: f"{workflow.basedir}/config.yaml"


include: "common.smk"


rule all:
    input:
        "results/figures/MYC_locus.pdf",


include: "rules/align.smk"
include: "rules/filter.smk"
include: "rules/peaks.smk"
include: "rules/overlap.smk"
include: "rules/plot.smk"
