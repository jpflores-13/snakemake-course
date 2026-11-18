# Exercise 4 solution: 04_call_peaks.sh
# Run from your working folder (the one with the data/ link in it):
#   snakemake -s path/to/answers/snakemakeify/ex4.smk -c 4
configfile: f"{workflow.basedir}/config.yaml"


include: "common.smk"


rule all:
    input:
        expand("results/peaks/{sample}_peaks.narrowPeak", sample=PEAK_SAMPLES),


include: "rules/align.smk"
include: "rules/filter.smk"
include: "rules/peaks.smk"
