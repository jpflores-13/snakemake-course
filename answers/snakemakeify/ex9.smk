# Exercise 9 solution: 09_ttseq_enhancers.R
# Run from your working folder (the one with the data/ link in it):
#   snakemake -s path/to/answers/snakemakeify/ex9.smk -c 4
configfile: f"{workflow.basedir}/config.yaml"


DATA = config["data"]


rule all:
    input:
        "results/ttseq/ttseq_enhancers_all.tsv",


include: "rules/ttseq.smk"
