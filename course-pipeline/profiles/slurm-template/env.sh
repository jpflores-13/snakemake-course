## Site setup template, sourced by RegPipe.sh and unlock.sh.
## Make python3 (>= 3.11, for Snakemake 8) and conda (>= 24.7.1) available here, e.g. `module load ...`
## or your own Miniforge (set REGPIPE_CONDA_ROOT).
source "${REGPIPE_CONDA_ROOT:-$HOME/miniforge3}/etc/profile.d/conda.sh"
conda activate base
