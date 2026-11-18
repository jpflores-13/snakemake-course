# Snakemake for genomics: a hands-on course

Source of the course site <https://jpflores-13.github.io/snakemake-course>:
two half-day workshops on Snakemake 8.27.1, built around a ChIP-seq and
DNase-seq pipeline (RegPipe) on public HCT116 data and the lab's own pipelines.

Lessons are CC BY 4.0 (`LICENSE`), code is MIT (`LICENSE-code`).
Author: JP Flores.

## Build the site

You need [Quarto](https://quarto.org) 1.11 or later, Python 3.11+ with
Snakemake 8.27.1, and (for the DAG pictures) Graphviz. The course environment
has all of them except Quarto:

```bash
git clone --recurse-submodules https://github.com/jpflores-13/snakemake-course.git
cd snakemake-course
conda env create -f envs/course.yml
conda activate snakemake-course

quarto preview          # live preview in the browser, re-renders on save
quarto render           # full build into _site/
quarto render lessons/01-rules.qmd   # one page (and its slides)
```

`quarto render` first runs `_scripts/generate.py` (see below). The rendered
site goes to `_site/`, which is not committed: GitHub Actions builds and
publishes it on every push to `main` (`.github/workflows/publish.yml`).

## How the pieces fit

### Pages and slides from one file

Each lesson in `lessons/` renders twice, as a web page and as reveal.js
slides. The lesson's front matter names the slides file:

```yaml
format:
  html: default
  revealjs:
    output-file: 01-rules-slides.html
```

Shared slide settings (theme, size, slide numbers, code highlighting) are in
`lessons/_metadata.yml`, and the slide theme is `styles/slides.scss`. The web
page links to its slides under *Also as: Slides*. Each `##` heading is one
slide; text that should be on the page only goes in
`::: {.content-hidden when-format="revealjs"}`, speaker notes in `::: {.notes}`.

The cheat sheet renders as a web page and a two-page PDF (Typst, built into
Quarto).

### Showing pipeline code: `{{< snippet >}}`

Pages never paste pipeline code. They pull it from the source, so it cannot go
stale:

```
{{< snippet repo="microcpipe" file="workflows/MicroCPipe.snakefile" rule="dedup" >}}
{{< snippet repo="ttpipe" file="workflows/rules/processing.smk" rule="star_align" >}}
{{< snippet repo="regpipe" file="workflows/rules/common.smk" def="filtered_bam" >}}
{{< snippet repo="chromsimpipe" file="workflows/ChromSimPipe.snakefile" checkpoint="name" >}}
{{< snippet repo="stopB" file="Snakefile" lines="10-40" >}}
```

| `repo=` | Folder |
|:--|:--|
| `microcpipe`, `ttpipe`, `chromsimpipe` | `pipelines/<name>` (git submodules) |
| `regpipe` | `course-pipeline/` |
| `stopA` ... `stopD` | `stopping-points/stopA/` ... |

Exactly one of `rule=`, `def=`, `checkpoint=` or `lines=` picks the part of
the file (none: the whole file). A rule runs from its `rule NAME:` line (it
may be indented, e.g. inside an `if`) to the next line at the same or a lower
indent; the `#` comment lines directly above it come along (`comments="false"`
leaves them out). Optional: `lang=` (default from the extension), `filename=`
(the label above the block). For the submodule pipelines a *view on GitHub*
link points at the exact lines in the pinned commit. A missing file or rule
shows a yellow warning box on the page and a warning in the render log; it
never stops the build.

### Showing real command output: `{{< generated >}}`

Dry runs, rule lists and DAG pictures on the pages are real output, made by
`_scripts/generate.py` (Quarto's `pre-render` step) and saved in
`_generated/`:

```
{{< generated name="microcpipe-dryrun" >}}
{{< generated name="ttpipe-dryrun" head="25" >}}      also: tail="10", lines="5-40"
{{< generated name="microcpipe-rulegraph" >}}          a graph: shown as an SVG picture
{{< generated name="microcpipe-rulegraph" as="code" >}} the dot text instead
```

If the output does not exist yet, the page shows a short note instead.

What `generate.py` runs:

1. **The lab pipelines**, against the dry-run fixtures each one ships in
   `tests/dryrun/` (the same commands as their own `tests/test_dryrun.py`):
   `<name>-dryrun`, `<name>-dag`, `<name>-rulegraph`, `<name>-list-rules`
   for `microcpipe` and `ttpipe`, plus `microcpipe-merge-dryrun` and
   `microcpipe-merge-rulegraph`. ChromSimPipe's test config needs a genome
   and peak files that are not in its repository, so only
   `chromsimpipe-list-rules` and `chromsimpipe-missing-input` (the real
   `MissingInputException` it prints) are made.
2. **RegPipe**, once `course-pipeline/` and the FASTQs in `data/` exist:
   `regpipe-dryrun`, `regpipe-dryrun-p`, `regpipe-dag`, `regpipe-rulegraph`,
   `regpipe-list-rules`, `regpipe-summary`.
3. **Commands requested by pages.** Put an HTML comment anywhere in a page
   under `lessons/`, `answers/`, `exercises/`, `field-guide/` or the top folder:

   ```
   <!-- GENERATE: stopB-dryrun | stopping-points/stopB | snakemake -n -c 1 -->
   ```

   That is `name | folder (relative to the course root) | command`. Everything
   after the second `|` is the command, so it may contain pipes. A command
   that writes a graph (`--dag`, `--rulegraph`) is saved as `.dot` and drawn
   to `.svg`; anything else is saved as `.txt` (stdout and stderr together).
   A command that fails is not saved; to show an error message on purpose,
   end the command with `|| true`.

Each command runs in a scratch copy of its folder (with `data/` and the other
folders linked in), so it never leaves `.snakemake/` or `output/` behind and
earlier runs do not change the result. Absolute paths in the output are made
relative. Results are cached by a hash of the command and its inputs, so a
render only re-runs what changed. `generate.py` never fails the render: it
logs problems and carries on. Outputs that no page asks for any more are
marked `stale` in `_generated/manifest.json` and can be deleted by hand.

**`_generated/` is committed**, so the site renders anywhere, including CI,
without the data or the tools. After changing a lesson's commands or the
pipelines, render locally and commit `_generated/` with the change.

Environment variables: `COURSE_SKIP_GENERATE=1` (use the committed outputs;
CI does this), `COURSE_FORCE_GENERATE=1` (ignore the cache),
`COURSE_GENERATE_ONLY=name1,name2`, `COURSE_EXTRA_PATH=/path/to/tools/bin`
(prepended to `PATH`, for commands that run real tools),
`COURSE_GENERATE_TIMEOUT=600` (seconds per command). Snakemake is taken from
`PATH`, else `/opt/course-venv/bin/snakemake`; Graphviz `dot` from `PATH`.

### The lab pipelines as pinned submodules

`pipelines/microcpipe`, `pipelines/ttpipe` and `pipelines/chromsimpipe` are
git submodules, each pinned to one commit, so snippets and dry runs do not
change when a pipeline does:

| Submodule | Repository | Pinned commit |
|:--|:--|:--|
| `pipelines/microcpipe` | https://github.com/jpflores-13/microcpipe | `253a6cc` |
| `pipelines/ttpipe` | https://github.com/jpflores-13/ttpipe | `ebdc210` |
| `pipelines/chromsimpipe` | https://github.com/jpflores-13/chromsimpipe | `e32dd36` |

They are shallow (`shallow = true` in `.gitmodules`). After cloning without
`--recurse-submodules`: `git submodule update --init --depth 1`.

#### Bumping a pin

When a pipeline changes and the course should follow:

```bash
cd pipelines/microcpipe
git fetch --depth 1 origin <new-sha>      # or: git fetch --depth 1 origin main
git checkout <new-sha>                    # or: git checkout FETCH_HEAD
cd ../..
quarto render                             # re-runs the dry runs; check the warnings
git add pipelines/microcpipe _generated/
git commit -m "Bump MicroCPipe to <short-sha>"
```

Then:

- read the render log for `snippet:` warnings (a rule renamed or removed) and
  fix the pages that use it;
- look at `git diff _generated/` for changed job counts, and update any page
  text that quotes them;
- update the pinned commit in the table above and in `SPEC.md` if it is
  still around.

The *view on GitHub* links follow the checked-out commit automatically.

## Folder map

```
_quarto.yml            site configuration (navbar, sidebars, formats)
index.qmd schedule.qmd setup.qmd glossary.qmd cheatsheet.qmd references.qmd about.qmd
lessons/               modules 0-8 (page + slides each); _metadata.yml = slide settings
answers/               answer keys, one per lesson, plus the Snakemake-ify answers
exercises/             the Snakemake-ify exercise
capstone.qmd           the capstone project
field-guide/           walk-throughs of MicroCPipe, TTpipe, ChromSimPipe and lab conventions
course-pipeline/       RegPipe, the finished course pipeline
stopping-points/       stopA-stopD: runnable snapshots learners can copy
snakemakeify/          the shell scripts the Snakemake-ify exercise converts
data/                  the course data (public, real) and data/prepare/, the workflow that made it
pipelines/             the lab pipelines (git submodules, pinned)
envs/course.yml        the learners' conda environment
_extensions/           the snippet and generated shortcodes (Lua)
_scripts/generate.py   pre-render: runs commands, writes _generated/
_generated/            committed command output used by the pages
styles/                theme.scss, theme-dark.scss (site), slides.scss (reveal.js)
.github/workflows/     publish.yml: build and deploy to GitHub Pages
```

## Learner environment

`envs/course.yml` pins Snakemake 8.27.1 (`snakemake-minimal` from bioconda)
and Python 3.12, and leaves the tools on their current releases. Every package
has builds for Linux (`linux-64`, also used by WSL2) and Intel macOS
(`osx-64`). On Apple silicon, `bioconductor-plotgardener` has no `osx-arm64`
build, so `setup.qmd` tells those learners to create the environment with
`CONDA_SUBDIR=osx-64` (Rosetta 2). Re-check this when bumping the
environment.
