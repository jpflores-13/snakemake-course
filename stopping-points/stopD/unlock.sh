#! /bin/bash -login

## Release the Snakemake lock after a failed or interrupted run, then
## start again with RegPipe.sh.
##
## Usage:
##   bash unlock.sh
##   bash unlock.sh --configfile other.yaml --profile profiles/<site>
## The profile is chosen as in RegPipe.sh: --profile, $REGPIPE_PROFILE,
## then hpcProfile in the config.

## Exit if any command fails
set -e

CONFIG="config/RegConfig.yaml"
PROFILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --configfile) CONFIG="$2";  shift 2 ;;
        --profile)    PROFILE="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

cfg() { sed -nE "s/^$1:[[:space:]]*['\"]?([^'\"#[:space:]]+).*/\1/p" "${CONFIG}" | head -1; }
PROFILE="${PROFILE:-${REGPIPE_PROFILE:-$(cfg hpcProfile)}}"

## Load this site's software
[[ -f "${PROFILE%/}/env.sh" ]] || { echo "No ${PROFILE%/}/env.sh: set --profile, \$REGPIPE_PROFILE or hpcProfile in ${CONFIG}" >&2; exit 1; }
source "${PROFILE%/}/env.sh"

## Unlock the workflow (the venv is not activated; see RegPipe.sh)
env/bin/python3 -m snakemake --unlock -s workflows/RegPipe.snakefile --cores 1 --configfile "${CONFIG}"

## Success message
echo "Directory unlocked, ready to rerun."
