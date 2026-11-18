# Exercise 1: 01_fastqc.sh
rule fastqc:
    input:
        f"{DATA}/fastq/{{sample}}.fastq.gz",
    output:
        html="results/fastqc/{sample}_fastqc.html",
        zip="results/fastqc/{sample}_fastqc.zip",
    log:
        "results/logs/fastqc/{sample}.log",
    shell:
        "fastqc --quiet --outdir results/fastqc {input} > {log} 2>&1"
