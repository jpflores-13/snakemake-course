# Exercise 6: 06_qc_summary.py
rule qc_summary:
    input:
        bams=expand("results/filter/{sample}.filt.bam", sample=SAMPLES),
        flagstats=expand("results/filter/{sample}.flagstat.txt", sample=SAMPLES),
        peaks=expand("results/peaks/{sample}_peaks.narrowPeak", sample=PEAK_SAMPLES),
    output:
        "results/qc/qc_summary.tsv",
    params:
        samples=SAMPLES,
        peak_samples=PEAK_SAMPLES,
    script:
        "../scripts/qc_summary.py"
