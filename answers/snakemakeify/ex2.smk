# Exercise 2 solution: 02_align.sh
# Run from your working folder (the one with the data/ link in it):
#   snakemake -s path/to/answers/snakemakeify/ex2.smk -c 4
configfile: f"{workflow.basedir}/config.yaml"


include: "common.smk"


rule all:
    input:
        expand("results/align/{sample}.bam", sample=SAMPLES),


include: "rules/align.smk"
