# Exercise 7 solution: 07_overlap.sh
# Run from your working folder (the one with the data/ link in it):
#   snakemake -s path/to/answers/snakemakeify/ex7.smk -c 4
configfile: f"{workflow.basedir}/config.yaml"


include: "common.smk"


rule all:
    input:
        "results/overlap/counts.txt",


include: "rules/align.smk"
include: "rules/filter.smk"
include: "rules/peaks.smk"
include: "rules/overlap.smk"
