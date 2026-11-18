"""Look up course inputs in the ENCODE REST API.

Imported by the Snakefile at parse time. Every JSON document is cached in
the scratch folder, so a rerun (or a dry run) uses exactly the metadata of
the first run. Delete <scratch>/metadata/ to refresh it.
"""

import json
import re
import urllib.request
from pathlib import Path


class EncodeLookupError(RuntimeError):
    pass


def get_json(portal, path, cache_dir):
    """Fetch <portal><path>?format=json, cached under cache_dir."""
    cache_dir = Path(cache_dir)
    cache_dir.mkdir(parents=True, exist_ok=True)
    name = re.sub(r"[^A-Za-z0-9]+", "_", path.strip("/")) + ".json"
    cached = cache_dir / name
    if cached.exists():
        return json.loads(cached.read_text())
    url = f"{portal.rstrip('/')}/{path.strip('/')}/?format=json"
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        doc = json.loads(resp.read().decode())
    cached.write_text(json.dumps(doc))
    return doc


def _analysis_id(item):
    return item if isinstance(item, str) else item["@id"]


def _rfa_rank(analysis):
    """ENCODE4 > ENCODE3 > anything else (lab custom, uniform)."""
    rfas = analysis.get("pipeline_award_rfas") or []
    nums = [int(m.group(1)) for r in rfas if (m := re.match(r"ENCODE(\d+)", r))]
    return max(nums, default=0)


def choose_analysis(exp, assembly, override=None):
    """Return (analysis @id, how it was chosen).

    1. An analysis accession from config wins.
    2. Otherwise the experiment's default_analysis.
    3. Otherwise the released analysis on `assembly` from the newest ENCODE
       phase. A tie is an error: pin one in config with `analysis:`.
    """
    if override:
        return f"/analyses/{override}/", "config override"
    if exp.get("default_analysis"):
        return _analysis_id(exp["default_analysis"]), "default_analysis"
    candidates = [
        a for a in exp.get("analyses", [])
        if isinstance(a, dict)
        and a.get("status") == "released"
        and a.get("assembly") == assembly
    ]
    if not candidates:
        raise EncodeLookupError(
            f"{exp['accession']}: no default_analysis and no released {assembly} analysis"
        )
    best = max(_rfa_rank(a) for a in candidates)
    top = [a for a in candidates if _rfa_rank(a) == best]
    if len(top) > 1:
        ids = ", ".join(a["@id"] for a in top)
        raise EncodeLookupError(
            f"{exp['accession']}: several candidate analyses ({ids}); set `analysis:` in config"
        )
    return top[0]["@id"], "fallback: newest released analysis on assembly"


def files_in_analysis(exp, analysis_id, assembly, output_type, file_format):
    """Released files of one output type that belong to the analysis."""
    hits = []
    for f in exp["files"]:
        if f.get("status") != "released":
            continue
        if f.get("assembly") != assembly or f.get("file_format") != file_format:
            continue
        if f.get("output_type") != output_type:
            continue
        ids = {_analysis_id(a) for a in f.get("analyses", [])}
        if analysis_id in ids:
            hits.append(f)
    return hits


def file_record(portal, f):
    return {
        "file": f["accession"],
        "url": portal.rstrip("/") + f["href"],
        "md5": f["md5sum"],
        "size": f.get("file_size"),
        "run_type": f.get("mapped_run_type") or f.get("run_type") or "unknown",
        "read_length": f.get("mapped_read_length"),
    }


def replicate_bams(portal, exp, analysis_id, assembly, output_type):
    """One BAM per biological replicate, as {bio_rep: record}."""
    bams = files_in_analysis(exp, analysis_id, assembly, output_type, "bam")
    by_rep = {}
    for f in bams:
        reps = f.get("biological_replicates") or []
        if len(reps) != 1:
            raise EncodeLookupError(
                f"{f['accession']}: expected one biological replicate, got {reps}"
            )
        rep = int(reps[0])
        if rep in by_rep:
            raise EncodeLookupError(
                f"{exp['accession']}: two '{output_type}' BAMs for replicate {rep} "
                f"({by_rep[rep]['file']}, {f['accession']})"
            )
        by_rep[rep] = file_record(portal, f)
    if not by_rep:
        raise EncodeLookupError(
            f"{exp['accession']}: no released '{output_type}' BAM in {analysis_id}"
        )
    return by_rep


def resolve_samples(cfg, cache_dir):
    """Build one row per FASTQ the workflow will write.

    Returns a list of dicts with the samplesheet fields plus the source
    BAM record and the experiment/analysis it came from.
    """
    portal, assembly = cfg["portal"], cfg["assembly"]
    out_type = cfg["bam_output_type"]
    rows = []

    def add_rows(exp, assay, target, override=None, control_of=None):
        analysis_id, how = choose_analysis(exp, assembly, override)
        cell = exp["biosample_ontology"]["term_name"]
        for rep, rec in sorted(replicate_bams(portal, exp, analysis_id, assembly, out_type).items()):
            rows.append({
                "Cell_Type": cell,
                "Assay": assay,
                "Target": target,
                "Bio_Rep": rep,
                "experiment": exp["accession"],
                "analysis": analysis_id.strip("/").split("/")[-1],
                "analysis_choice": how,
                "control_of": control_of,
                **rec,
            })
        return cell

    for entry in cfg["experiments"]:
        exp = get_json(portal, f"experiments/{entry['accession']}", cache_dir)
        target = entry.get("target")
        if not target:
            t = exp.get("target")
            if not isinstance(t, dict):
                raise EncodeLookupError(f"{entry['accession']}: no target; set `target:` in config")
            target = t["label"]
        add_rows(exp, entry["assay"], target, entry.get("analysis"))
        for ctrl in exp.get("possible_controls", []):
            acc = ctrl if isinstance(ctrl, str) else ctrl["accession"]
            acc = acc.strip("/").split("/")[-1]
            cexp = get_json(portal, f"experiments/{acc}", cache_dir)
            add_rows(cexp, entry["assay"], cfg["control_prefix"] + target,
                     control_of=entry["accession"])

    for r in rows:
        r["sample"] = f"{r['Cell_Type']}_{r['Target']}_{r['Bio_Rep']}"
    names = [r["sample"] for r in rows]
    dupes = {n for n in names if names.count(n) > 1}
    if dupes:
        raise EncodeLookupError(f"duplicate sample names: {sorted(dupes)}")
    return rows


def pair_controls(rows):
    """Control sample name for each row (NA for controls and DNase).

    Rule: ChIP replicate n uses control replicate n of its control
    experiment when that replicate exists, otherwise control replicate 1
    (the lowest-numbered one if there is no replicate 1).
    """
    controls = {}
    for r in rows:
        if r["control_of"]:
            controls.setdefault(r["control_of"], {})[r["Bio_Rep"]] = r["sample"]
    for r in rows:
        if r["control_of"] or r["experiment"] not in controls:
            r["Control"] = "NA"
            continue
        reps = controls[r["experiment"]]
        r["Control"] = reps.get(r["Bio_Rep"]) or reps.get(1) or reps[min(reps)]
    return rows


def single_file(portal, accession, cache_dir):
    f = get_json(portal, f"files/{accession}", cache_dir)
    rec = file_record(portal, f)
    rec["dataset"] = f["dataset"].strip("/").split("/")[-1]
    return rec


def analysis_file(cfg, experiment, output_type, file_format, cache_dir):
    """The one released file of output_type in the experiment's chosen analysis."""
    portal, assembly = cfg["portal"], cfg["assembly"]
    exp = get_json(portal, f"experiments/{experiment}", cache_dir)
    analysis_id, how = choose_analysis(exp, assembly)
    hits = files_in_analysis(exp, analysis_id, assembly, output_type, file_format)
    if len(hits) != 1:
        raise EncodeLookupError(
            f"{experiment}: expected one '{output_type}' file in {analysis_id}, got {len(hits)}"
        )
    rec = file_record(portal, hits[0])
    rec["dataset"] = experiment
    rec["analysis"] = analysis_id.strip("/").split("/")[-1]
    rec["analysis_choice"] = how
    return rec
