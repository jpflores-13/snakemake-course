"""Snakemake dry runs of RegPipe against the real course data in ../data.

A dry run (-n) reads the samplesheet and config, builds the DAG and checks that
every input file exists; it runs no tools. The expected number of jobs per rule
is worked out from the samplesheet here, the same way the workflow does it, so
the tests keep passing when you add or remove samples.

Run from the folder that holds RegPipe.sh:   python -m pytest tests/
Skipped when snakemake is not installed or the course data are missing.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pandas as pd
import pytest
import yaml

ROOT = Path(__file__).resolve().parents[1]
CONFIG = yaml.safe_load((ROOT / "config" / "RegConfig.yaml").read_text())
DATA = ROOT / CONFIG["dataDir"]

## also find snakemake next to the running interpreter (a venv used without being activated)
SNAKEMAKE = shutil.which("snakemake", path=os.pathsep.join([os.path.dirname(sys.executable),
                                                            os.environ.get("PATH", "")]))
pytestmark = [
    pytest.mark.skipif(SNAKEMAKE is None, reason="snakemake not installed"),
    pytest.mark.skipif(not (DATA / "fastq").is_dir(), reason=f"course data not found in {DATA}"),
]


def read_samplesheet():
    """The samplesheet as the workflow reads it (see workflows/rules/common.smk)."""
    sheet = pd.read_csv(ROOT / CONFIG["samplesheet"], sep="\t", dtype=str, keep_default_na=False)
    sheet["sample"] = sheet[CONFIG["fileNamesFrom"]].agg("_".join, axis=1)
    return sheet


def expected_jobs(scatter_chunks=0):
    """Rule -> number of jobs for a run from scratch, derived from the samplesheet."""
    sheet = read_samplesheet()
    controls = set(sheet.loc[sheet["Control"] != "NA", "Control"])
    n_samples = len(sheet)
    peak_samples = sheet[~sheet["sample"].isin(controls)]
    n_peaks = len(peak_samples)
    n_targets = peak_samples["Target"].nunique()

    jobs = {
        "all": 1,
        "fastqc": n_samples,
        "bowtie2_index": 1,
        "filter": n_samples,
        "bigwig": n_samples,
        "call_peaks": n_peaks,          # every sample that is not someone's control
        "frip": n_peaks,
        "consensus_peaks": n_targets,   # one per Target with peaks
        "qc_table": 1,
        "ctcf_rad21_overlap": 1,
    }
    if CONFIG.get("make_locus_plot", True):
        jobs["locus_plot"] = 1
    if scatter_chunks:
        jobs["split_fastq"] = n_samples
        jobs["align_chunk"] = n_samples * scatter_chunks
        jobs["merge_chunks"] = n_samples
    else:
        jobs["align"] = n_samples
    jobs["total"] = sum(jobs.values())
    return jobs


def dry_run(tmp_path, *extra):
    """Dry run into an empty output folder, so every job is listed (nothing is up to date)."""
    cmd = [SNAKEMAKE, "-n", "--nolock", "-s", "workflows/RegPipe.snakefile", "--cores", "1",
           "--config", f"outputDir={tmp_path}", *extra]
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)


def job_counts(result):
    """Rule -> job count from the 'Job stats' table that a dry run prints."""
    counts, started = {}, False
    for line in result.stdout.splitlines():
        if line.startswith("Job stats"):
            started = True
            continue
        if started:
            parts = line.split()
            if len(parts) == 2 and parts[1].isdigit():
                counts[parts[0]] = int(parts[1])
            elif not line.strip() and counts:
                break
    return counts


def test_dry_run_job_counts(tmp_path):
    r = dry_run(tmp_path)
    assert r.returncode == 0, r.stderr
    assert job_counts(r) == expected_jobs()


def test_controls_are_wired_to_their_chip(tmp_path):
    """Each ChIP sample's call_peaks job reads its control's filtered BAM; DNase has no -c."""
    r = dry_run(tmp_path, "--printshellcmds")
    assert r.returncode == 0, r.stderr
    sheet = read_samplesheet()
    commands = [ln for ln in r.stdout.splitlines() if ln.strip().startswith("macs3 callpeak")]
    for _, row in sheet.iterrows():
        if row["Control"] == "NA":
            continue
        cmd = next(c for c in commands if f"-n {row['sample']} " in c)
        assert f"{row['Control']}_filtered.bam" in cmd
    for name in sheet.loc[sheet["Assay"].str.startswith("DNase"), "sample"]:
        cmd = next(c for c in commands if f"-n {name} " in c)
        assert " -c " not in cmd


def test_scatter_dry_run(tmp_path):
    """scatter_chunks: N replaces each align job by split_fastq + N align_chunk + merge_chunks."""
    chunks = 3
    r = dry_run(tmp_path, f"scatter_chunks={chunks}")
    assert r.returncode == 0, r.stderr
    assert job_counts(r) == expected_jobs(scatter_chunks=chunks)


def test_unknown_control_is_rejected(tmp_path):
    """A Control that names no sample stops the run before any job starts."""
    sheet = read_samplesheet().drop(columns="sample")
    first_chip = sheet.index[sheet["Control"] != "NA"][0]
    sheet.loc[first_chip, "Control"] = "HCT116_no-such-control_1"
    bad = tmp_path / "bad_samplesheet.txt"
    sheet.to_csv(bad, sep="\t", index=False)
    r = dry_run(tmp_path, f"samplesheet={bad}")
    assert r.returncode != 0
    assert "not in the samplesheet" in r.stderr + r.stdout
