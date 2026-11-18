#! /bin/bash -login
#SBATCH -J RegPipe
#SBATCH -t 2-00:00:00
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -c 1
#SBATCH --mem=8gb    # building the conda envs on a first run needs > 4 GB
#SBATCH -o "%x-%j.out"
#SBATCH --mail-type=END,FAIL,TIME_LIMIT_80

## RegPipe launcher (same pattern as MicroCPipe / TTpipe / ChromSimPipe).
##
## Usage (from the folder that holds this script):
##   bash   RegPipe.sh                         # profiles/local (no scheduler)
##   bash   RegPipe.sh -n                      # dry run: list jobs only
##   sbatch RegPipe.sh                         # SLURM cluster (set the profile first, below)
##   bash   RegPipe.sh --configfile other.yaml # use a different config
##   bash   RegPipe.sh --profile profiles/<site>   # override hpcProfile
##
## The compute site is a profile folder: its env.sh loads software, its
## config.yaml tells Snakemake how to run jobs. It is chosen by, in order:
## --profile, $REGPIPE_PROFILE, then hpcProfile in the config.
## Per-cluster settings that stay out of git (e.g. in ~/.bashrc):
##   export REGPIPE_PROFILE=profiles/longleaf        # this cluster's profile
##   export REGPIPE_OUTPUT_ROOT=/work/users/$USER    # where a relative outputDir goes
## Email: `export REGPIPE_EMAIL=you@university.edu` and the workflow mails you when it
## starts, finishes or fails (`notify:` in the config).
## Any other arguments are passed straight to snakemake (e.g. -n, --forcerun filter).

## Exit if any command fails
set -e

## Config file and profile (overridable with --configfile / --profile)
CONFIG="config/RegConfig.yaml"
PROFILE=""
ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --configfile) CONFIG="$2";  shift 2 ;;
        --profile)    PROFILE="$2"; shift 2 ;;
        *)            ARGS+=("$1"); shift ;;
    esac
done

## Read a top-level value from the config, e.g. `cfg outputDir`
cfg() { sed -nE "s/^$1:[[:space:]]*['\"]?([^'\"#[:space:]]+).*/\1/p" "${CONFIG}" | head -1; }
PROFILE="${PROFILE:-${REGPIPE_PROFILE:-$(cfg hpcProfile)}}"
PROFILE="${PROFILE%/}"

## Output directory, resolved the same way as workflows/rules/common.smk
OUTDIR="$(cfg outputDir)"
OUTDIR="${OUTDIR:-output}"
OUTDIR="${OUTDIR/#\~/$HOME}"
[[ "${OUTDIR}" = /* ]] || OUTDIR="${REGPIPE_OUTPUT_ROOT:-$PWD}/${OUTDIR}"

## Stop early if the profile still contains an unedited <placeholder> (e.g. slurm_account: <account>)
if grep -qE '^[^#]*<[A-Za-z ]+>' "${PROFILE}/config.yaml" 2>/dev/null; then
    echo "${PROFILE}/config.yaml still has <placeholder> values: edit them for your cluster first" >&2
    exit 1
fi

## Load this site's software (python3, conda)
[[ -f "${PROFILE}/env.sh" ]] || { echo "No ${PROFILE}/env.sh: set --profile, \$REGPIPE_PROFILE or hpcProfile in ${CONFIG}" >&2; exit 1; }
source "${PROFILE}/env.sh"

## Create the virtual environment with Snakemake. It is NOT activated: its bin/ must not be on
## PATH inside jobs, where a venv `python` ahead of the rule's conda env would run the rule's
## scripts without the env's packages. (A shell command that runs Python in a lab pipeline calls
## $CONDA_PREFIX/bin/python for the same reason.)
[ -d env ] || python3 -m venv env
env/bin/python3 -m pip install -q -r config/requirements.txt

## SLURM job logs (only for profiles that use the SLURM executor)
EXTRA=()
if grep -qE "^executor:[[:space:]]*slurm" "${PROFILE}/config.yaml"; then
    SLURM_LOGS="${OUTDIR}/logs_slurm"
    mkdir -p "${SLURM_LOGS}"
    EXTRA+=(--slurm-logdir "${SLURM_LOGS}" --max-jobs-per-second 5 --max-status-checks-per-second 0.5)
fi

## Execute the RegPipe snakemake workflow
env/bin/python3 -m snakemake -s workflows/RegPipe.snakefile --profile "${PROFILE}" --configfile "${CONFIG}" \
    --rerun-incomplete --keep-going -p "${EXTRA[@]}" "${ARGS[@]}"

## Success message
echo "Workflow completed successfully!"
