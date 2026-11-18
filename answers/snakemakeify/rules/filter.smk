# Exercise 3: 03_filter.sh
rule filter_reads:
    input:
        bam="results/align/{sample}.bam",
        blacklist=f"{DATA}/reference/blacklist.bed.gz",
    output:
        temp("results/filter/{sample}.noBL.bam"),
    params:
        mapq=config["filter"]["mapq"],
    shell:
        "samtools view -b -q {params.mapq} {input.bam}"
        " | bedtools intersect -v -abam stdin -b {input.blacklist} > {output}"


rule markdup:
    input:
        "results/filter/{sample}.noBL.bam",
    output:
        bam="results/filter/{sample}.filt.bam",
        bai="results/filter/{sample}.filt.bam.bai",
    log:
        "results/logs/markdup/{sample}.log",
    shell:
        "samtools markdup -r {input} {output.bam} 2> {log}"
        " && samtools index {output.bam}"


rule flagstat:
    input:
        "results/filter/{sample}.filt.bam",
    output:
        "results/filter/{sample}.flagstat.txt",
    shell:
        "samtools flagstat {input} > {output}"


rule bigwig:
    input:
        bam="results/filter/{sample}.filt.bam",
        bai="results/filter/{sample}.filt.bam.bai",
    output:
        "results/tracks/{sample}.bw",
    params:
        binsize=config["bigwig"]["binsize"],
        extend=config["bigwig"]["extend"],
    log:
        "results/logs/bigwig/{sample}.log",
    threads: 4
    shell:
        "bamCoverage -b {input.bam} -o {output} --normalizeUsing CPM"
        " --binSize {params.binsize} --extendReads {params.extend} -p {threads} 2> {log}"
