# Exercise 2: 02_align.sh
rule reference:
    input:
        f"{DATA}/reference/chr8_course.fa.gz",
    output:
        fa="results/index/chr8_course.fa",
        fai="results/index/chr8_course.fa.fai",
    shell:
        "gunzip -c {input} > {output.fa} && samtools faidx {output.fa}"


rule bowtie2_index:
    input:
        rules.reference.output.fa,
    output:
        multiext("results/index/chr8_course",
                 ".1.bt2", ".2.bt2", ".3.bt2", ".4.bt2", ".rev.1.bt2", ".rev.2.bt2"),
    params:
        prefix="results/index/chr8_course",
    log:
        "results/logs/bowtie2_index.log",
    threads: 4
    shell:
        "bowtie2-build --threads {threads} {input} {params.prefix} > {log} 2>&1"


rule align:
    input:
        fq=f"{DATA}/fastq/{{sample}}.fastq.gz",
        index=rules.bowtie2_index.output,
    output:
        bam="results/align/{sample}.bam",
        bai="results/align/{sample}.bam.bai",
    params:
        prefix=rules.bowtie2_index.params.prefix,
    log:
        "results/logs/align/{sample}.bowtie2.log",
    threads: 4
    shell:
        "bowtie2 -p {threads} -x {params.prefix} -U {input.fq} 2> {log}"
        " | samtools sort -@ 2 -o {output.bam} -"
        " && samtools index {output.bam}"
