# Exercise 6 solution: 06_qc_summary.py
# Run from your working folder (the one with the data/ link in it):
#   snakemake -s path/to/answers/snakemakeify/ex6.smk -c 4
configfile: f"{workflow.basedir}/config.yaml"


include: "common.smk"


rule all:
    input:
        "results/qc/qc_summary.tsv",


include: "rules/align.smk"
include: "rules/filter.smk"
include: "rules/peaks.smk"
include: "rules/qc.smk"
