#!/bin/bash
# FastQC on the raw reads for every sample.
# Run it from the folder you want the results in:
#   bash 01_fastqc.sh

DATA=~/snakemake-course/data
SAMPLES="HCT116_CTCF_1 HCT116_CTCF_2 HCT116_H3K27ac_1 HCT116_H3K27ac_2 HCT116_DNase_1 HCT116_DNase_2 HCT116_input-CTCF_1 HCT116_input-H3K27ac_1"

mkdir -p fastqc

for s in $SAMPLES; do
    if [ -f fastqc/${s}_fastqc.html ]; then
        echo "fastqc: $s already done, skipping"
        continue
    fi
    echo "fastqc: $s"
    fastqc --quiet --outdir fastqc $DATA/fastq/$s.fastq.gz
done

echo "fastqc: finished"
