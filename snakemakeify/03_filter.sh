#!/bin/bash
# Filter the alignments from 02_align.sh and make a CPM bigWig per sample.
#   MAPQ >= 30, drop reads in the ENCODE blacklist, remove duplicates.
# Writes <sample>.filt.bam (+ .bai), <sample>.flagstat.txt and tracks/<sample>.bw
#   bash 03_filter.sh

DATA=~/snakemake-course/data
BLACKLIST=$DATA/reference/blacklist.bed.gz
MAPQ=30
THREADS=4
SAMPLES="HCT116_CTCF_1 HCT116_CTCF_2 HCT116_H3K27ac_1 HCT116_H3K27ac_2 HCT116_DNase_1 HCT116_DNase_2 HCT116_input-CTCF_1 HCT116_input-H3K27ac_1"

mkdir -p tracks

for s in $SAMPLES; do
    if [ -f $s.filt.bam ]; then
        echo "$s already filtered, skipping"
        continue
    fi
    echo "filtering $s"

    samtools view -b -q $MAPQ $s.bam > $s.q$MAPQ.bam
    bedtools intersect -v -abam $s.q$MAPQ.bam -b $BLACKLIST > $s.noBL.bam
    samtools markdup -r $s.noBL.bam $s.filt.bam 2> $s.markdup.log
    samtools index $s.filt.bam
    rm $s.q$MAPQ.bam $s.noBL.bam

    samtools flagstat $s.filt.bam > $s.flagstat.txt

    bamCoverage -b $s.filt.bam -o tracks/$s.bw \
        --normalizeUsing CPM --binSize 10 --extendReads 200 -p $THREADS
done
