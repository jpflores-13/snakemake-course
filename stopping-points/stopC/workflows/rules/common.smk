## Shared helpers for RegPipe: the samplesheet, output paths and the targets of `rule all`.
## The samplesheet and config are read here, once; every rule file uses the names below.
## Rules set only `threads:`; memory and time live in profiles/<site>/config.yaml
## (set-threads / set-resources), as in the lab's other pipelines.

import os
import re
import sys
import pandas as pd


##### Paths #####
def outdir():
    """outputDir, with a relative path placed under $REGPIPE_OUTPUT_ROOT when set."""
    d = os.path.expanduser(str(config.get("outputDir", "output")))
    if not os.path.isabs(d):
        d = os.path.join(os.environ.get("REGPIPE_OUTPUT_ROOT", os.getcwd()), d)
    return d.rstrip("/")


OUT = outdir()
LOGS = OUT + "/logs"
BENCH = OUT + "/benchmarks"

## The workflow files live in workflows/, the envs and scripts one level up.
## workflow.basedir is the folder of the main Snakefile, wherever you launch from.
ENVS = os.path.join(workflow.basedir, "..", "envs")
SCRIPTS = os.path.join(workflow.basedir, "..", "scripts")

DATA = os.path.expanduser(str(config.get("dataDir", ".")))


def data_path(path):
    """A path from the samplesheet or config: relative ones are read from dataDir."""
    return os.path.join(DATA, os.path.expanduser(str(path)))


##### Samplesheet #####
## keep_default_na=False: pandas would otherwise turn the text "NA" in the Control
## column into a missing value (NaN), and "NA" is how the samplesheet says "no control".
samples = pd.read_csv(config["samplesheet"], sep="\t", dtype=str, keep_default_na=False)

_required = {"Assay", "Target", "Control", "Read1", "Sequencing_Directory"} | set(config["fileNamesFrom"])
_missing = _required - set(samples.columns)
if _missing:
    raise ValueError(f"{config['samplesheet']} is missing column(s): {sorted(_missing)}")

## Sample name = the fileNamesFrom columns joined with '_' (e.g. HCT116_CTCF_1)
samples["sample"] = samples[config["fileNamesFrom"]].agg("_".join, axis=1)
if samples["sample"].duplicated().any():
    dup = sorted(samples.loc[samples["sample"].duplicated(), "sample"])
    raise ValueError(f"Duplicate sample name(s) {dup} from fileNamesFrom {config['fileNamesFrom']}; "
                     "add a column that tells them apart.")
samples["fastq"] = [data_path(os.path.join(d, f)) for d, f in zip(samples["Sequencing_Directory"], samples["Read1"])]

SAMPLE_TABLE = samples.set_index("sample")
SAMPLES = list(samples["sample"])

## A sample is a control when another sample names it in its Control column.
_controls_named = set(samples.loc[samples["Control"] != "NA", "Control"])
_unknown = _controls_named - set(SAMPLES)
if _unknown:
    raise ValueError(f"Control column names sample(s) that are not in the samplesheet: {sorted(_unknown)}")
CONTROLS = [s for s in SAMPLES if s in _controls_named]

## Peaks are called on every sample that is not a control (ChIP and DNase).
PEAK_SAMPLES = [s for s in SAMPLES if s not in CONTROLS]
## Targets with peaks (CTCF, H3K27ac, DNase) and their replicates
TARGETS = list(dict.fromkeys(SAMPLE_TABLE.loc[PEAK_SAMPLES, "Target"]))
SAMPLES_BY_TARGET = {t: [s for s in PEAK_SAMPLES if SAMPLE_TABLE.loc[s, "Target"] == t] for t in TARGETS}

## Wildcards may only take these values. Without this, a pattern like
## {sample}_peaks.narrowPeak could match a file name in more than one way.
wildcard_constraints:
    sample = "|".join(map(re.escape, SAMPLES)),
    target = "|".join(map(re.escape, TARGETS)),


##### Switches #####
MAKE_LOCUS_PLOT = bool(config.get("make_locus_plot", True))
OVERLAP_TARGET = config["overlapTarget"]
if OVERLAP_TARGET not in TARGETS:
    raise ValueError(f"overlapTarget {OVERLAP_TARGET!r} is not a peak-called Target in the samplesheet {TARGETS}")
for _t in config["locusPlot"]["targets"] if MAKE_LOCUS_PLOT else []:
    if _t not in TARGETS:
        raise ValueError(f"locusPlot target {_t!r} is not a peak-called Target in the samplesheet {TARGETS}")

## TT-seq: one entry per bigWig, e.g. {"track": "TTseq_1_plus", "strand": "plus", "path": ...}
TTSEQ = config.get("ttseq", {}) or {}
TTSEQ_ENABLED = bool(TTSEQ.get("enabled", False))
TTSEQ_TRACKS = []
if TTSEQ_ENABLED:
    for _rep, _strands in TTSEQ["bigwigs"].items():
        for _strand, _path in _strands.items():
            if _strand not in ("plus", "minus"):
                raise ValueError(f"ttseq bigwigs: strand must be plus or minus, got {_strand!r} for {_rep}")
            TTSEQ_TRACKS.append({"track": f"{_rep}_{_strand}", "strand": _strand, "path": data_path(_path)})
    for _t in TTSEQ["overlapTargets"]:
        if _t not in TARGETS:
            raise ValueError(f"ttseq overlapTargets: {_t!r} is not a peak-called Target in the samplesheet {TARGETS}")
TTSEQ_ANNOTATIONS = {name: data_path(p) for name, p in TTSEQ.get("annotations", {}).items()} if TTSEQ_ENABLED else {}

WINDOW = config["window"]
## deepTools writes regions as chrom:start:end (colons, not samtools' chrom:start-end)
DEEPTOOLS_REGION = f"{WINDOW['chrom']}:{WINDOW['start']}:{WINDOW['end']}"


##### Output files (one place, so rule files and `rule all` agree) #####
def filtered_bam(sample):
    return f"{OUT}/{sample}/{sample}_filtered.bam"


def peak_file(sample):
    return f"{OUT}/peaks/{sample}_peaks.narrowPeak"


def consensus_file(target):
    return f"{OUT}/consensus/{target}_consensus.bed"


def bigwig_file(sample):
    return f"{OUT}/tracks/{sample}.bw"


LOCUS_PLOT = f"{OUT}/figures/{config['locusPlot']['name']}_locus.pdf"


def all_targets():
    """Everything `rule all` asks for."""
    t = []
    t += [f"{OUT}/{s}/fastqc/{s}_fastqc.html" for s in SAMPLES]
    t += [filtered_bam(s) for s in SAMPLES]
    t += [bigwig_file(s) for s in SAMPLES]
    t += [peak_file(s) for s in PEAK_SAMPLES]
    t += [consensus_file(target) for target in TARGETS]
    t += [f"{OUT}/qc/qc_table.tsv", f"{OUT}/qc/ctcf_rad21_overlap.tsv"]
    if MAKE_LOCUS_PLOT:
        t.append(LOCUS_PLOT)
    if TTSEQ_ENABLED:
        t.append(f"{OUT}/qc/enhancer_activity.tsv")
    return t


##### Input functions (used by the rule files) #####
def fastq(wildcards):
    """The raw FASTQ of a sample, from the samplesheet (dataDir + Sequencing_Directory + Read1)."""
    return SAMPLE_TABLE.loc[wildcards.sample, "fastq"]


def control_bam(wildcards):
    """The filtered BAM of this sample's control, or nothing when Control is NA (DNase).
    Returning [] from an input function means "no input here", so the rule still runs."""
    control = SAMPLE_TABLE.loc[wildcards.sample, "Control"]
    if control == "NA":
        return []
    return filtered_bam(control)


def macs3_args(wildcards):
    """Extra MACS3 arguments for this sample's Target (config macs3: targetArgs:)."""
    args = config["macs3"]["targetArgs"]
    return args.get(SAMPLE_TABLE.loc[wildcards.sample, "Target"], args["default"])


##### Email notifications (see `notify:` in the config) #####
NOTIFY = config.get("notify", {}) or {}
EMAIL = os.environ.get("REGPIPE_EMAIL") or NOTIFY.get("email") or ""


def notify(event, body, run_name):
    """Send one message for a workflow event, if an address and the event are configured."""
    if not EMAIL or event not in NOTIFY.get("events", ["start", "success", "error"]):
        return
    import shlex, socket, subprocess
    subject = f"{run_name}: {event}"
    body = f"Run:     {run_name}\nOutput:  {OUT}\nHost:    {socket.gethostname()}\n\n{body}\n"
    cmd = NOTIFY.get("command", "mail -s {subject} {email}").format(
        subject=shlex.quote(subject), email=shlex.quote(EMAIL))
    try:
        subprocess.run(cmd, shell=True, input=body, text=True, timeout=60, check=True)
    except Exception as e:  # a failed email must never fail the workflow
        print(f"Could not send '{event}' email to {EMAIL}: {e}", file=sys.stderr)
