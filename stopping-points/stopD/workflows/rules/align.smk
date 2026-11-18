## Reads -> filtered BAMs: fastqc, bowtie2_index, align (or the scatter rules), filter.
## Paths and sample metadata come from rules/common.smk.



##### QC of the raw reads #####
rule fastqc:
    input:
        fastq = fastq,
    output:
        html = OUT + "/{sample}/fastqc/{sample}_fastqc.html",
        zip = OUT + "/{sample}/fastqc/{sample}_fastqc.zip",
    log:
        LOGS + "/fastqc/{sample}.log",
    benchmark:
        BENCH + "/fastqc/{sample}.tsv",
    threads: 1
    conda: ENVS + "/regpipe_align.yml"
    params:
        tmp = OUT + "/{sample}/fastqc/tmp",
    shell:
        """
        rm -rf {params.tmp} && mkdir -p {params.tmp}
        fastqc --threads {threads} --outdir {params.tmp} {input.fastq} > {log} 2>&1
        ## FastQC names its files after the FASTQ, which need not be the sample name
        mv {params.tmp}/*_fastqc.html {output.html}
        mv {params.tmp}/*_fastqc.zip {output.zip}
        rm -rf {params.tmp}
        """


##### Reference index #####
## bowtie2-build writes six files (genome.1.bt2 ... genome.rev.2.bt2), or .bt2l files
## for genomes over 4 Gb. Declaring the whole folder with directory() means the rule
## does not need to know those names. Module 7 compares this with the other common
## pattern, listing a `.done` sentinel file as the output.
## Snakemake does not create a directory() output for you, hence the mkdir.
rule bowtie2_index:
    input:
        fasta = data_path(config["reference"]["fasta"]),
    output:
        directory(OUT + "/reference/bowtie2_index"),
    log:
        LOGS + "/bowtie2_index/bowtie2_index.log",
    benchmark:
        BENCH + "/bowtie2_index/bowtie2_index.tsv",
    threads: 4
    conda: ENVS + "/regpipe_align.yml"
    params:
        prefix = OUT + "/reference/bowtie2_index/genome",
    shell:
        """
        mkdir -p {output}
        bowtie2-build --threads {threads} {input.fasta} {params.prefix} > {log} 2>&1
        """


## bowtie2 is given the index as a prefix (folder + basename), not as a folder
INDEX_PREFIX = OUT + "/reference/bowtie2_index/genome"


##### Alignment #####
## The aligned BAM is temp(): Snakemake deletes it once `filter` has used it.
if SCATTER == 0:

    ## One job per FASTQ. bowtie2 writes SAM to stdout; samtools sort reads it from
    ## the pipe, so no SAM file ever touches the disk.
    rule align:
        input:
            fastq = fastq,
            index = rules.bowtie2_index.output,
        output:
            bam = temp(OUT + "/{sample}/{sample}_aligned.bam"),
        log:
            LOGS + "/align/{sample}.log",
        benchmark:
            BENCH + "/align/{sample}.tsv",
        threads: 4
        conda: ENVS + "/regpipe_align.yml"
        params:
            index = INDEX_PREFIX,
            args = config["bowtie2Args"],
            tmp = OUT + "/{sample}/{sample}_sort_tmp",
        shell:
            """
            bowtie2 -p {threads} {params.args} -x {params.index} -U {input.fastq} 2> {log} \
                | samtools sort -@ {threads} -T {params.tmp} -o {output.bam} - 2>> {log}
            """

else:

    ## Scatter / gather (module 7): split each FASTQ into SCATTER chunks, align every
    ## chunk as its own job, merge the sorted chunk BAMs into the same file `align`
    ## would have written. `filter` and everything after it do not change.
    ## scatter.chunks() / gather.chunks() expand {scatteritem} to 1-of-N ... N-of-N;
    ## {{sample}} has double braces so it stays a wildcard.
    scattergather:
        chunks = SCATTER,

    rule split_fastq:
        input:
            fastq = fastq,
        output:
            temp(scatter.chunks(OUT + "/{{sample}}/chunks/{{sample}}_{scatteritem}.fastq.gz")),
        log:
            LOGS + "/split_fastq/{sample}.log",
        benchmark:
            BENCH + "/split_fastq/{sample}.tsv",
        threads: 1
        conda: ENVS + "/regpipe_align.yml"
        script:
            SCRIPTS + "/split_fastq.py"

    rule align_chunk:
        input:
            fastq = OUT + "/{sample}/chunks/{sample}_{scatteritem}.fastq.gz",
            index = rules.bowtie2_index.output,
        output:
            bam = temp(OUT + "/{sample}/chunks/{sample}_{scatteritem}.bam"),
        log:
            LOGS + "/align_chunk/{sample}_{scatteritem}.log",
        benchmark:
            BENCH + "/align_chunk/{sample}_{scatteritem}.tsv",
        threads: 4
        conda: ENVS + "/regpipe_align.yml"
        params:
            index = INDEX_PREFIX,
            args = config["bowtie2Args"],
            tmp = OUT + "/{sample}/chunks/{sample}_{scatteritem}_sort_tmp",
        shell:
            """
            bowtie2 -p {threads} {params.args} -x {params.index} -U {input.fastq} 2> {log} \
                | samtools sort -@ {threads} -T {params.tmp} -o {output.bam} - 2>> {log}
            """

    rule merge_chunks:
        input:
            gather.chunks(OUT + "/{{sample}}/chunks/{{sample}}_{scatteritem}.bam"),
        output:
            bam = temp(OUT + "/{sample}/{sample}_aligned.bam"),
        log:
            LOGS + "/merge_chunks/{sample}.log",
        benchmark:
            BENCH + "/merge_chunks/{sample}.tsv",
        threads: 4
        conda: ENVS + "/regpipe_align.yml"
        shell:
            "samtools merge -@ {threads} -o {output.bam} {input} 2> {log}"


##### Filtering #####
## 1. flagstat of everything bowtie2 wrote (unaligned reads included): reads in, reads aligned
## 2. keep reads with MAPQ >= minMapq and none of the excludeFlags
## 3. drop reads in ENCODE blacklist regions (bedtools intersect -v)
## 4. remove PCR/optical duplicates (samtools markdup -r). These are single-end reads, so
##    the coordinate-sorted BAM can go straight to markdup: `samtools fixmate -m` is
##    only needed to add mate information to paired-end reads.
rule filter:
    input:
        bam = OUT + "/{sample}/{sample}_aligned.bam",
        blacklist = data_path(config["reference"]["blacklist"]),
    output:
        bam = OUT + "/{sample}/{sample}_filtered.bam",
        bai = OUT + "/{sample}/{sample}_filtered.bam.bai",
        flagstat = OUT + "/{sample}/{sample}_aligned_flagstat.tsv",
        markdup = OUT + "/{sample}/{sample}_markdup.txt",
    log:
        LOGS + "/filter/{sample}.log",
    benchmark:
        BENCH + "/filter/{sample}.tsv",
    threads: 2
    conda: ENVS + "/regpipe_align.yml"
    params:
        mapq = config["minMapq"],
        flags = config["excludeFlags"],
    shell:
        """
        samtools flagstat -@ {threads} -O tsv {input.bam} > {output.flagstat} 2> {log}
        samtools view -u -q {params.mapq} -F {params.flags} {input.bam} 2>> {log} \
            | bedtools intersect -v -abam stdin -b {input.blacklist} 2>> {log} \
            | samtools markdup -r -f {output.markdup} -@ {threads} - {output.bam} 2>> {log}
        samtools index {output.bam} 2>> {log}
        """
