#!/bin/bash
# Build the bowtie2 index (first time only), then align every sample.
# Writes <sample>.bam, <sample>.bam.bai and <sample>.bowtie2.log here.
#   bash 02_align.sh

DATA=~/snakemake-course/data
REF=$DATA/reference/chr8_course.fa.gz
THREADS=4
SAMPLES="HCT116_CTCF_1 HCT116_CTCF_2 HCT116_input-CTCF_1 HCT116_input-CTCF_2
         HCT116_H3K27ac_1 HCT116_H3K27ac_2 HCT116_input-H3K27ac_1 HCT116_input-H3K27ac_2
         HCT116_DNase_1 HCT116_DNase_2"

# index takes a few minutes, so only build it once
if [ ! -f chr8_course.1.bt2 ]; then
    echo "building bowtie2 index"
    gunzip -c $REF > chr8_course.fa
    samtools faidx chr8_course.fa    # bedtools wants the .fai later
    bowtie2-build --threads $THREADS chr8_course.fa chr8_course > bowtie2-build.log 2>&1
fi

for s in $SAMPLES; do
    if [ -f $s.bam ]; then
        echo "$s.bam exists, skipping"
        continue
    fi
    echo "aligning $s"
    bowtie2 -p $THREADS -x chr8_course -U $DATA/fastq/$s.fastq.gz 2> $s.bowtie2.log \
        | samtools sort -@ 2 -o $s.bam -
    samtools index $s.bam
done

grep -H "overall alignment rate" *.bowtie2.log
