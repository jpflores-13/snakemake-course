# Stopping points

Each folder here is a complete, runnable copy of the course pipeline as it
stands at the end of a module. If you fell behind, copy the folder for the
point you reached and carry on from there:

```bash
cp -r stopping-points/stopB my-regpipe
cd my-regpipe
```

Every stopping point reads the course data from `../../data`, so run it from
inside its own folder (or keep your copy two levels below the course root, or
change `DATA` / `dataDir` to point at the data). Each one is a strict superset
of the one before.

| Folder | State after | What is in it | Run it with |
|---|---|---|---|
| `stopA/` | module 2 | one `Snakefile`: `fastqc`, `bowtie2_index`, `align`, `filter`; the samples are a Python list; `{sample}` wildcards and `expand()` | `snakemake -n`, then `snakemake --cores 4` (tools from the course env) |
| `stopB/` | module 4 (end of day 1) | + `config/RegConfig.yaml` and `RegSamplesheet.txt` read with pandas, input functions (the control lookup), `call_peaks`, `consensus_peaks`, `bigwig`; `log:`, `benchmark:`, `threads:`, `params:`, `temp()`, `conda:` with `envs/` | `snakemake --cores 4 --use-conda` |
| `stopC/` | module 6 | + the lab layout: `RegPipe.sh`, `unlock.sh`, `profiles/` (local, longleaf, slurm-template), `workflows/RegPipe.snakefile` with `workflows/rules/*.smk`, switches (`make_locus_plot`, `ttseq: enabled`), `script:` rules in Python (`frip`, `qc_table`, `ctcf_rad21_overlap`) and R (`locus_plot`, `enhancer_activity`), `onstart`/`onsuccess`/`onerror` with email | `bash RegPipe.sh -n`, then `bash RegPipe.sh` |
| `stopD/` | module 8 | = `course-pipeline/`: + `scatter_chunks` (`scattergather:`), `bowtie2_index` as a `directory()` output, `tests/test_dryrun.py`, `README.md` | as stopC; `python -m pytest tests/` |

`stopD` is a copy of `course-pipeline/` (not a link), and differs from it in
one line: `dataDir: '../../data'` instead of `'../data'` in
`config/RegConfig.yaml`.

## Seeing what changed

The code in each stage is kept as close as possible to the final pipeline, so
a diff shows only what the module added:

```bash
cd stopping-points
diff -u stopA/Snakefile stopB/Snakefile           # module 3-4: config, samplesheet, peaks, logs, conda
diff -ru stopC stopD                              # module 7-8: scatter, directory(), tests
diff -ru stopD ../course-pipeline                 # only dataDir
```

stopB to stopC is mostly a move from one file to many. Compare a rule at a
time, e.g. the `filter` rule in `stopB/Snakefile` and in
`stopC/workflows/rules/align.smk`, or:

```bash
diff -u <(sed -n '/^rule call_peaks/,/^rule consensus_peaks/p' stopB/Snakefile) \
        <(sed -n '/^rule call_peaks/,/^rule consensus_peaks/p' stopC/workflows/rules/peaks.smk)
```

## Things that differ on purpose

- `bowtie2_index` lists its six output files with `multiext()` in stopA-stopC
  and declares the whole folder with `directory()` in stopD (module 7 compares
  the two, and a `.done` sentinel file).
- stopA calls the tools straight from your `PATH`; from stopB on, each rule
  names a conda env file and you run with `--use-conda` (the launcher and
  profiles in stopC do that for you).
- stopA and stopB write to `output/` next to the Snakefile; from stopC on,
  `outputDir` can also be placed under `$REGPIPE_OUTPUT_ROOT` (module 5).
