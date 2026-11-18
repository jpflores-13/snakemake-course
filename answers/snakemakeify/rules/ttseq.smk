# Exercise 9: 09_ttseq_enhancers.R
TT = config["ttseq"]


wildcard_constraints:
    rep=r"\d+",
    strand="|".join(TT["strands"]),


rule ttseq_signal:
    input:
        bigwig=f"{DATA}/{TT['bigwig']}",
        enhancers=f"{DATA}/{TT['enhancers']}",
    output:
        "results/ttseq/rep{rep}_{strand}.tsv",
    log:
        "results/logs/ttseq/rep{rep}_{strand}.log",
    script:
        "../scripts/ttseq_signal.R"


rule ttseq_tables:
    input:
        expand("results/ttseq/rep{rep}_{strand}.tsv",
               rep=TT["reps"], strand=TT["strands"]),
    output:
        reps=expand("results/ttseq/ttseq_enhancers_rep{rep}.tsv", rep=TT["reps"]),
        combined="results/ttseq/ttseq_enhancers_all.tsv",
    params:
        reps=TT["reps"],
        strands=TT["strands"],
    log:
        "results/logs/ttseq/tables.log",
    script:
        "../scripts/ttseq_tables.R"
