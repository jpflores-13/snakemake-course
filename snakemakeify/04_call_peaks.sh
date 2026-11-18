#!/bin/bash
# Call peaks with MACS3 on the filtered BAMs from 03_filter.sh.
# ChIP samples use the control named in the samplesheet's Control column;
# DNase has no control and is centered on the cut sites instead.
# Duplicates are already gone (03), so MACS3 keeps every read.
# Writes peaks/<sample>_peaks.narrowPeak, _summits.bed, _peaks.xls
#   bash 04_call_peaks.sh

DATA=~/snakemake-course/data
SHEET=$DATA/samplesheet.txt
GSIZE=5000001     # mappable bases in the 5 Mb window, not 'hs'
QVAL=0.01

mkdir -p peaks

# columns: Project Cell_Type Assay Target Bio_Rep Control Read1 Sequencing_Directory
tail -n +2 $SHEET | while IFS=$'\t' read project cell assay target rep control read1 seqdir; do
    s=${cell}_${target}_${rep}

    # controls get used by the ChIP samples, no peaks for them
    if [[ $target == input* ]]; then
        continue
    fi
    if [ -f peaks/${s}_peaks.narrowPeak ]; then
        echo "$s: peaks exist, skipping"
        continue
    fi

    if [ "$control" == "NA" ]; then
        echo "$s: no control"
        macs3 callpeak -t $s.filt.bam -f BAM -g $GSIZE -n $s --outdir peaks \
            -q $QVAL --keep-dup all --nomodel --shift -75 --extsize 150 2> peaks/$s.macs3.log
    else
        echo "$s: control $control"
        macs3 callpeak -t $s.filt.bam -c $control.filt.bam -f BAM -g $GSIZE -n $s \
            --outdir peaks -q $QVAL --keep-dup all --nomodel --extsize 200 2> peaks/$s.macs3.log
    fi
done

wc -l peaks/*_peaks.narrowPeak
