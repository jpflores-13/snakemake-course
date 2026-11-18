## Site setup for a local machine (laptop or workstation), sourced by RegPipe.sh and unlock.sh.
## Needs python3 (>= 3.11, for Snakemake 8) and conda/mamba (conda >= 24.7.1).
## Uses your own Miniforge (one-time install, ~0.5 GB):
##   https://github.com/conda-forge/miniforge  (follow the installer for your OS)
## Set REGPIPE_CONDA_ROOT if you installed it somewhere else.
source "${REGPIPE_CONDA_ROOT:-$HOME/miniforge3}/etc/profile.d/conda.sh"
conda activate base
