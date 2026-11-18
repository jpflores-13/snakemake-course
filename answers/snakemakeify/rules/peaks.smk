# Exercise 4: 04_call_peaks.sh
def macs3_inputs(wildcards):
    """Treatment BAM, plus the control BAM named in the samplesheet."""
    inputs = {"treatment": f"results/filter/{wildcards.sample}.filt.bam"}
    control = sheet.loc[wildcards.sample, "Control"]
    if control != "NA":
        inputs["control"] = f"results/filter/{control}.filt.bam"
    return inputs


def macs3_options(wildcards, input):
    if "control" in input.keys():
        return f"-c {input.control} {config['macs3']['with_control']}"
    return config["macs3"]["no_control"]


rule call_peaks:
    input:
        unpack(macs3_inputs),
    output:
        peaks="results/peaks/{sample}_peaks.narrowPeak",
        summits="results/peaks/{sample}_summits.bed",
        xls="results/peaks/{sample}_peaks.xls",
    params:
        gsize=config["macs3"]["gsize"],
        qvalue=config["macs3"]["qvalue"],
        options=macs3_options,
    log:
        "results/logs/macs3/{sample}.log",
    shell:
        "macs3 callpeak -t {input.treatment} {params.options} -f BAM"
        " -g {params.gsize} -q {params.qvalue}"
        " -n {wildcards.sample} --outdir results/peaks 2> {log}"
