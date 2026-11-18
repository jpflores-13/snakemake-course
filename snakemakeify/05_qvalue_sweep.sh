#!/bin/bash
# How many CTCF peaks do we get at different MACS3 q-value cutoffs?
# Re-calls CTCF peaks at each cutoff and makes a small table.
# Writes sweep/<sample>_q<q>_peaks.narrowPeak and sweep/sweep_counts.tsv
#   bash 05_qvalue_sweep.sh   (after 03_filter.sh)

GSIZE=hs
CONTROL=HCT116_input-CTCF_1
QVALUES="0.05 0.01 0.001 0.0001"

mkdir -p sweep

for s in HCT116_CTCF_1 HCT116_CTCF_2; do
    for q in $QVALUES; do
        if [ -f sweep/${s}_q${q}_peaks.narrowPeak ]; then
            continue
        fi
        echo "$s q=$q"
        macs3 callpeak -t $s.filt.bam -c $CONTROL.filt.bam -f BAM -g $GSIZE \
            -n ${s}_q${q} --outdir sweep -q $q 2> sweep/${s}_q${q}.macs3.log
    done
done

# table: sample, q, number of peaks
echo -e "sample\tqvalue\tn_peaks" > sweep/sweep_counts.tsv
for s in HCT116_CTCF_1 HCT116_CTCF_2; do
    for q in $QVALUES; do
        n=$(wc -l < sweep/${s}_q${q}_peaks.narrowPeak)
        echo -e "$s\t$q\t$n" >> sweep/sweep_counts.tsv
    done
done

cat sweep/sweep_counts.tsv
