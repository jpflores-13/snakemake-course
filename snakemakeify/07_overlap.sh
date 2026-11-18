#!/bin/bash
# Replicate-consensus peaks per target, and which CTCF peaks have RAD21.
#   consensus = rep 1 peaks that overlap a rep 2 peak
# Also makes +-100 bp windows around the CTCF summits (for motif work later).
# Writes overlap/<target>_consensus.bed, overlap/CTCF_with_RAD21.bed,
#        overlap/CTCF_summits_200bp.bed, overlap/counts.txt
#   bash 07_overlap.sh   (after 04_call_peaks.sh)

DATA=~/snakemake-course/data
RAD21=$DATA/peaks/RAD21_ENCFF391AAM.bed.gz

mkdir -p overlap

for t in CTCF H3K27ac DNase; do
    if [ ! -f overlap/${t}_consensus.bed ]; then
        bedtools intersect -u \
            -a peaks/HCT116_${t}_1_peaks.narrowPeak \
            -b peaks/HCT116_${t}_2_peaks.narrowPeak > overlap/${t}_consensus.bed
    fi
done

if [ ! -f overlap/CTCF_with_RAD21.bed ]; then
    bedtools intersect -u -a overlap/CTCF_consensus.bed -b $RAD21 > overlap/CTCF_with_RAD21.bed
fi

if [ ! -f overlap/CTCF_summits_200bp.bed ]; then
    bedtools slop -b 100 -g chr8_course.fa.fai \
        -i peaks/HCT116_CTCF_1_summits.bed > overlap/CTCF_summits_200bp.bed
fi

wc -l overlap/*.bed | tee overlap/counts.txt
