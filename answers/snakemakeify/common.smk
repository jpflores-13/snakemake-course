# Shared by every exercise Snakefile: read the samplesheet once and
# build the sample lists the rules need.
import pandas as pd

DATA = config["data"]

sheet = pd.read_csv(f"{DATA}/samplesheet.txt", sep="\t", dtype=str,
                    keep_default_na=False)
sheet["sample"] = sheet[config["fileNamesFrom"]].agg("_".join, axis=1)
sheet = sheet.set_index("sample", drop=False)

SAMPLES = sheet.index.tolist()
CONTROLS = sorted(set(sheet["Control"]) - {"NA"})
PEAK_SAMPLES = [s for s in SAMPLES if s not in CONTROLS]
TARGETS = sorted(set(sheet.loc[PEAK_SAMPLES, "Target"]))


def reps_of(target):
    """Peak-calling samples of one target, in samplesheet order."""
    return [s for s in PEAK_SAMPLES if sheet.loc[s, "Target"] == target]


wildcard_constraints:
    sample="|".join(SAMPLES),
    target="|".join(TARGETS),
    q=r"[0-9.]+",
