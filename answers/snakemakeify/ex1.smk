# Exercise 1 solution: 01_fastqc.sh
# Run from your working folder (the one with the data/ link in it):
#   snakemake -s path/to/answers/snakemakeify/ex1.smk -c 4
configfile: f"{workflow.basedir}/config.yaml"


include: "common.smk"


rule all:
    input:
        expand("results/fastqc/{sample}_fastqc.html", sample=SAMPLES),


include: "rules/fastqc.smk"
