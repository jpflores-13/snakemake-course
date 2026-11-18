## Peaks: call_peaks (MACS3, per sample) and consensus_peaks (per target).


## MACS3 names its files after -n inside --outdir: <sample>_peaks.narrowPeak,
## <sample>_peaks.xls and <sample>_summits.bed.
## params.control uses `input`: the "-c" flag is only written when there is a control file.
rule call_peaks:
    input:
        treatment = lambda wildcards: filtered_bam(wildcards.sample),
        control = control_bam,
    output:
        peaks = OUT + "/peaks/{sample}_peaks.narrowPeak",
        xls = OUT + "/peaks/{sample}_peaks.xls",
        summits = OUT + "/peaks/{sample}_summits.bed",
    log:
        LOGS + "/call_peaks/{sample}.log",
    benchmark:
        BENCH + "/call_peaks/{sample}.tsv",
    threads: 1
    conda: ENVS + "/regpipe_peaks.yml"
    params:
        outdir = lambda wildcards, output: os.path.dirname(output.peaks),
        control = lambda wildcards, input: f"-c {input.control}" if input.control else "",
        gsize = config["effectiveGenomeSize"],
        qvalue = config["macs3"]["qvalue"],
        keep_dup = config["macs3"]["keepDup"],
        extra = macs3_args,
    shell:
        """
        macs3 callpeak -t {input.treatment} {params.control} -f BAM \
            -g {params.gsize} -q {params.qvalue} --keep-dup {params.keep_dup} {params.extra} \
            -n {wildcards.sample} --outdir {params.outdir} > {log} 2>&1
        """


## Consensus peaks of one target: the peaks of the first replicate that overlap a
## peak in every other replicate (bedtools intersect -u, once per other replicate).
## Controls have no peaks, so they never get here (TARGETS excludes them).
rule consensus_peaks:
    input:
        first = lambda wildcards: peak_file(SAMPLES_BY_TARGET[wildcards.target][0]),
        others = lambda wildcards: [peak_file(s) for s in SAMPLES_BY_TARGET[wildcards.target][1:]],
    output:
        bed = OUT + "/consensus/{target}_consensus.bed",
    log:
        LOGS + "/consensus_peaks/{target}.log",
    benchmark:
        BENCH + "/consensus_peaks/{target}.tsv",
    threads: 1
    conda: ENVS + "/regpipe_peaks.yml"
    params:
        tmp = OUT + "/consensus/{target}_consensus.tmp",
    shell:
        """
        : > {log}
        cut -f 1-6 {input.first} > {params.tmp}
        for other in {input.others}; do
            bedtools intersect -u -a {params.tmp} -b $other > {params.tmp}.next 2>> {log}
            mv {params.tmp}.next {params.tmp}
        done
        sort -k1,1 -k2,2n {params.tmp} > {output.bed}
        rm {params.tmp}
        """
