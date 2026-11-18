# Exercise 3 solution: 03_filter.sh
# Run from your working folder (the one with the data/ link in it):
#   snakemake -s path/to/answers/snakemakeify/ex3.smk -c 4
configfile: f"{workflow.basedir}/config.yaml"


include: "common.smk"


rule all:
    input:
        expand("results/filter/{sample}.flagstat.txt", sample=SAMPLES),
        expand("results/tracks/{sample}.bw", sample=SAMPLES),


include: "rules/align.smk"
include: "rules/filter.smk"
