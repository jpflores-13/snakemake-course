# Exercise 5 solution: 05_qvalue_sweep.sh
# Run from your working folder (the one with the data/ link in it):
#   snakemake -s path/to/answers/snakemakeify/ex5.smk -c 4
configfile: f"{workflow.basedir}/config.yaml"


include: "common.smk"


rule all:
    input:
        "results/sweep/sweep_counts.tsv",


include: "rules/align.smk"
include: "rules/filter.smk"
include: "rules/sweep.smk"
