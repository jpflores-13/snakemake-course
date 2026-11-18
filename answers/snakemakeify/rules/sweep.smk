# Exercise 5: 05_qvalue_sweep.sh
SWEEP_SAMPLES = reps_of(config["sweep"]["target"])
QVALUES = config["sweep"]["qvalues"]


rule sweep_call:
    input:
        treatment="results/filter/{sample}.filt.bam",
        control=lambda wc: f"results/filter/{sheet.loc[wc.sample, 'Control']}.filt.bam",
    output:
        "results/sweep/{sample}_q{q}_peaks.narrowPeak",
    params:
        gsize=config["macs3"]["gsize"],
    log:
        "results/logs/sweep/{sample}_q{q}.log",
    shell:
        "macs3 callpeak -t {input.treatment} -c {input.control} -f BAM -g {params.gsize}"
        " -n {wildcards.sample}_q{wildcards.q} --outdir results/sweep -q {wildcards.q} 2> {log}"


rule sweep_counts:
    input:
        expand("results/sweep/{sample}_q{q}_peaks.narrowPeak",
               sample=SWEEP_SAMPLES, q=QVALUES),
    output:
        "results/sweep/sweep_counts.tsv",
    run:
        # expand() loops over q fastest, so this matches the input order
        labels = [(s, q) for s in SWEEP_SAMPLES for q in QVALUES]
        with open(output[0], "w") as out:
            out.write("sample\tqvalue\tn_peaks\n")
            for (s, q), path in zip(labels, input):
                with open(path) as fh:
                    n = sum(1 for _ in fh)
                out.write(f"{s}\t{q}\t{n}\n")
