#!/bin/bash
# Whole HCT116 analysis, start to finish. Run from an empty folder:
#   mkdir -p ~/hct116-legacy && cd ~/hct116-legacy
#   bash ~/snakemake-course/snakemakeify/run_all.sh 2>&1 | tee run_all.log
# Each step skips samples it has already done, so it is safe to re-run.

SCRIPTS=$(dirname $0)

echo "== 01 fastqc";   bash $SCRIPTS/01_fastqc.sh
echo "== 02 align";    bash $SCRIPTS/02_align.sh
echo "== 03 filter";   bash $SCRIPTS/03_filter.sh
echo "== 04 peaks";    bash $SCRIPTS/04_call_peaks.sh
echo "== 05 sweep";    bash $SCRIPTS/05_qvalue_sweep.sh
echo "== 06 qc";       python3 $SCRIPTS/06_qc_summary.py
echo "== 07 overlap";  bash $SCRIPTS/07_overlap.sh
echo "== 08 plot";     Rscript $SCRIPTS/08_locus_plot.R

echo "all done"
