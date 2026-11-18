# Exercise 7: 07_overlap.sh
rule consensus_peaks:
    input:
        lambda wc: expand("results/peaks/{sample}_peaks.narrowPeak",
                          sample=reps_of(wc.target)),
    output:
        "results/overlap/{target}_consensus.bed",
    params:
        rep1=lambda wc, input: input[0],
        others=lambda wc, input: input[1:],
    shell:
        # replicate 1 peaks that overlap a peak in any other replicate
        "bedtools intersect -u -a {params.rep1} -b {params.others} > {output}"


rule ctcf_rad21_overlap:
    input:
        ctcf="results/overlap/CTCF_consensus.bed",
        rad21=f"{DATA}/peaks/RAD21_ENCFF391AAM.bed.gz",
    output:
        "results/overlap/CTCF_with_RAD21.bed",
    shell:
        "bedtools intersect -u -a {input.ctcf} -b {input.rad21} > {output}"


rule ctcf_summit_windows:
    input:
        summits=lambda wc: f"results/peaks/{reps_of('CTCF')[0]}_summits.bed",
        fai=rules.reference.output.fai,
    output:
        "results/overlap/CTCF_summits_200bp.bed",
    shell:
        "bedtools slop -b 100 -g {input.fai} -i {input.summits} > {output}"


rule overlap_counts:
    input:
        expand("results/overlap/{target}_consensus.bed", target=TARGETS),
        rules.ctcf_rad21_overlap.output,
        rules.ctcf_summit_windows.output,
    output:
        "results/overlap/counts.txt",
    shell:
        "wc -l {input} > {output}"
