// Simple numbering for non-book documents
#let equation-numbering = "(1)"
#let callout-numbering = "1"
#let subfloat-numbering(n-super, subfloat-idx) = {
  numbering("1a", n-super, subfloat-idx)
}

// Theorem configuration for theorion
// Simple numbering for non-book documents (no heading inheritance)
#let theorem-inherited-levels = 0

// Theorem numbering format (can be overridden by extensions for appendix support)
// This function returns the numbering pattern to use
#let theorem-numbering(loc) = "1.1"

// Default theorem render function
#let theorem-render(prefix: none, title: "", full-title: auto, body) = {
  if full-title != "" and full-title != auto and full-title != none {
    strong[#full-title.]
    h(0.5em)
  }
  body
}
// Some definitions presupposed by pandoc's typst output.
#let content-to-string(content) = {
  if content.has("text") {
    content.text
  } else if content.has("children") {
    content.children.map(content-to-string).join("")
  } else if content.has("body") {
    content-to-string(content.body)
  } else if content == [ ] {
    " "
  }
}

#let horizontalrule = line(start: (25%,0%), end: (75%,0%))

#let endnote(num, contents) = [
  #stack(dir: ltr, spacing: 3pt, super[#num], contents)
]

#show terms.item: it => block(breakable: false)[
  #text(weight: "bold")[#it.term]
  #block(inset: (left: 1.5em, top: -0.4em))[#it.description]
]

// Some quarto-specific definitions.

#show raw.where(block: true): set block(
    fill: luma(230),
    width: 100%,
    inset: 8pt,
    radius: 2pt
  )

#let block_with_new_content(old_block, new_content) = {
  let fields = old_block.fields()
  let _ = fields.remove("body")
  if fields.at("below", default: none) != none {
    // TODO: this is a hack because below is a "synthesized element"
    // according to the experts in the typst discord...
    fields.below = fields.below.abs
  }
  block.with(..fields)(new_content)
}

#let empty(v) = {
  if type(v) == str {
    // two dollar signs here because we're technically inside
    // a Pandoc template :grimace:
    v.matches(regex("^\\s*$")).at(0, default: none) != none
  } else if type(v) == content {
    if v.at("text", default: none) != none {
      return empty(v.text)
    }
    for child in v.at("children", default: ()) {
      if not empty(child) {
        return false
      }
    }
    return true
  }

}

// Subfloats
// This is a technique that we adapted from https://github.com/tingerrr/subpar/
#let quartosubfloatcounter = counter("quartosubfloatcounter")

#let quarto_super(
  kind: str,
  caption: none,
  label: none,
  supplement: str,
  position: none,
  subcapnumbering: "(a)",
  body,
) = {
  context {
    let figcounter = counter(figure.where(kind: kind))
    let n-super = figcounter.get().first() + 1
    set figure.caption(position: position)
    [#figure(
      kind: kind,
      supplement: supplement,
      caption: caption,
      {
        show figure.where(kind: kind): set figure(numbering: _ => {
          let subfloat-idx = quartosubfloatcounter.get().first() + 1
          subfloat-numbering(n-super, subfloat-idx)
        })
        show figure.where(kind: kind): set figure.caption(position: position)
        show figure.where(kind: kind): set figure(outlined: false)

        show figure: it => {
          let num = numbering(subcapnumbering, n-super, quartosubfloatcounter.get().first() + 1)
          show figure.caption: it => block({
            num.slice(2) // I don't understand why the numbering contains output that it really shouldn't, but this fixes it shrug?
            [ ]
            it.body
          })

          quartosubfloatcounter.step()
          it
          counter(figure.where(kind: it.kind)).update(n => n - 1)
        }

        quartosubfloatcounter.update(0)
        body
      }
    )#label]
  }
}

// callout rendering
// this is a figure show rule because callouts are crossreferenceable
#show figure: it => {
  if type(it.kind) != str {
    return it
  }
  let kind_match = it.kind.matches(regex("^quarto-callout-(.*)")).at(0, default: none)
  if kind_match == none {
    return it
  }
  let kind = kind_match.captures.at(0, default: "other")
  kind = upper(kind.first()) + kind.slice(1)
  // now we pull apart the callout and reassemble it with the crossref name and counter

  // when we cleanup pandoc's emitted code to avoid spaces this will have to change
  let old_callout = it.body.children.at(1).body.children.at(1)
  let old_title_block = old_callout.body.children.at(0)
  let children = old_title_block.body.body.children
  let old_title = if children.len() == 1 {
    children.at(0)  // no icon: title at index 0
  } else {
    children.at(1)  // with icon: title at index 1
  }

  // TODO use custom separator if available
  // Use the figure's counter display which handles chapter-based numbering
  // (when numbering is a function that includes the heading counter)
  let callout_num = it.counter.display(it.numbering)
  let new_title = if empty(old_title) {
    [#kind #callout_num]
  } else {
    [#kind #callout_num: #old_title]
  }

  let new_title_block = block_with_new_content(
    old_title_block,
    block_with_new_content(
      old_title_block.body,
      if children.len() == 1 {
        new_title  // no icon: just the title
      } else {
        children.at(0) + new_title  // with icon: preserve icon block + new title
      }))

  align(left, block_with_new_content(old_callout,
    block(below: 0pt, new_title_block) +
    old_callout.body.children.at(1)))
}

// 2023-10-09: #fa-icon("fa-info") is not working, so we'll eval "#fa-info()" instead
#let callout(body: [], title: "Callout", background_color: rgb("#dddddd"), icon: none, icon_color: black, body_background_color: white) = {
  block(
    breakable: false, 
    fill: background_color, 
    stroke: (paint: icon_color, thickness: 0.5pt, cap: "round"), 
    width: 100%, 
    radius: 2pt,
    block(
      inset: 1pt,
      width: 100%, 
      below: 0pt, 
      block(
        fill: background_color,
        width: 100%,
        inset: 8pt)[#if icon != none [#text(icon_color, weight: 900)[#icon] ]#title]) +
      if(body != []){
        block(
          inset: 1pt, 
          width: 100%, 
          block(fill: body_background_color, width: 100%, inset: 8pt, body))
      }
    )
}


// syntax highlighting functions from skylighting:
/* Function definitions for syntax highlighting generated by skylighting: */
#let EndLine() = raw("\n")
#let Skylighting(fill: none, number: false, start: 1, sourcelines) = {
   let blocks = []
   let lnum = start - 1
   let bgcolor = rgb("#f1f3f5")
   for ln in sourcelines {
     if number {
       lnum = lnum + 1
       blocks = blocks + box(width: if start + sourcelines.len() > 999 { 30pt } else { 24pt }, text(fill: rgb("#aaaaaa"), [ #lnum ]))
     }
     blocks = blocks + ln + EndLine()
   }
   block(fill: bgcolor, width: 100%, inset: 8pt, radius: 2pt, blocks)
}
#let AlertTok(s) = text(fill: rgb("#ad0000"),raw(s))
#let AnnotationTok(s) = text(fill: rgb("#5e5e5e"),raw(s))
#let AttributeTok(s) = text(fill: rgb("#657422"),raw(s))
#let BaseNTok(s) = text(fill: rgb("#ad0000"),raw(s))
#let BuiltInTok(s) = text(fill: rgb("#003b4f"),raw(s))
#let CharTok(s) = text(fill: rgb("#20794d"),raw(s))
#let CommentTok(s) = text(fill: rgb("#5e5e5e"),raw(s))
#let CommentVarTok(s) = text(style: "italic",fill: rgb("#5e5e5e"),raw(s))
#let ConstantTok(s) = text(fill: rgb("#8f5902"),raw(s))
#let ControlFlowTok(s) = text(weight: "bold",fill: rgb("#003b4f"),raw(s))
#let DataTypeTok(s) = text(fill: rgb("#ad0000"),raw(s))
#let DecValTok(s) = text(fill: rgb("#ad0000"),raw(s))
#let DocumentationTok(s) = text(style: "italic",fill: rgb("#5e5e5e"),raw(s))
#let ErrorTok(s) = text(fill: rgb("#ad0000"),raw(s))
#let ExtensionTok(s) = text(fill: rgb("#003b4f"),raw(s))
#let FloatTok(s) = text(fill: rgb("#ad0000"),raw(s))
#let FunctionTok(s) = text(fill: rgb("#4758ab"),raw(s))
#let ImportTok(s) = text(fill: rgb("#00769e"),raw(s))
#let InformationTok(s) = text(fill: rgb("#5e5e5e"),raw(s))
#let KeywordTok(s) = text(weight: "bold",fill: rgb("#003b4f"),raw(s))
#let NormalTok(s) = text(fill: rgb("#003b4f"),raw(s))
#let OperatorTok(s) = text(fill: rgb("#5e5e5e"),raw(s))
#let OtherTok(s) = text(fill: rgb("#003b4f"),raw(s))
#let PreprocessorTok(s) = text(fill: rgb("#ad0000"),raw(s))
#let RegionMarkerTok(s) = text(fill: rgb("#003b4f"),raw(s))
#let SpecialCharTok(s) = text(fill: rgb("#5e5e5e"),raw(s))
#let SpecialStringTok(s) = text(fill: rgb("#20794d"),raw(s))
#let StringTok(s) = text(fill: rgb("#20794d"),raw(s))
#let VariableTok(s) = text(fill: rgb("#111111"),raw(s))
#let VerbatimStringTok(s) = text(fill: rgb("#20794d"),raw(s))
#let WarningTok(s) = text(style: "italic",fill: rgb("#5e5e5e"),raw(s))



#let article(
  title: none,
  subtitle: none,
  authors: none,
  keywords: (),
  date: none,
  abstract-title: none,
  abstract: none,
  thanks: none,
  cols: 1,
  lang: "en",
  region: "US",
  font: none,
  fontsize: 11pt,
  title-size: 1.5em,
  subtitle-size: 1.25em,
  heading-family: none,
  heading-weight: "bold",
  heading-style: "normal",
  heading-color: black,
  heading-line-height: 0.65em,
  mathfont: none,
  codefont: none,
  linestretch: 1,
  sectionnumbering: none,
  linkcolor: none,
  citecolor: none,
  filecolor: none,
  toc: false,
  toc_title: none,
  toc_depth: none,
  toc_indent: 1.5em,
  lof: false,
  lof-title: none,
  lot: false,
  lot-title: none,
  doc,
) = {
  // Set document metadata for PDF accessibility
  set document(title: title, keywords: keywords)
  set document(
    author: authors.map(author => content-to-string(author.name)).join(", ", last: " & "),
  ) if authors != none and authors != ()
  set par(
    justify: true,
    leading: linestretch * 0.65em
  )
  set text(lang: lang,
           region: region,
           size: fontsize)
  set text(font: font) if font != none
  show math.equation: set text(font: mathfont) if mathfont != none
  show raw: set text(font: codefont) if codefont != none

  set heading(numbering: sectionnumbering)

  show link: set text(fill: rgb(content-to-string(linkcolor))) if linkcolor != none
  show ref: set text(fill: rgb(content-to-string(citecolor))) if citecolor != none
  show link: this => {
    if filecolor != none and type(this.dest) == label {
      text(this, fill: rgb(content-to-string(filecolor)))
    } else {
      text(this)
    }
   }

  let has-title-block = title != none or (authors != none and authors != ()) or date != none or abstract != none
  if has-title-block {
    place(
      top,
      float: true,
      scope: "parent",
      clearance: 4mm,
      block(below: 1em, width: 100%)[

        #if title != none {
          align(center, block(inset: 2em)[
            #set par(leading: heading-line-height) if heading-line-height != none
            #set text(font: heading-family) if heading-family != none
            #set text(weight: heading-weight)
            #set text(style: heading-style) if heading-style != "normal"
            #set text(fill: heading-color) if heading-color != black

            #text(size: title-size)[#title #if thanks != none {
              footnote(thanks, numbering: "*")
              counter(footnote).update(n => n - 1)
            }]
            #(if subtitle != none {
              parbreak()
              text(size: subtitle-size)[#subtitle]
            })
          ])
        }

        #if authors != none and authors != () {
          let count = authors.len()
          let ncols = calc.min(count, 3)
          grid(
            columns: (1fr,) * ncols,
            row-gutter: 1.5em,
            ..authors.map(author =>
                align(center)[
                  #author.name \
                  #author.affiliation \
                  #author.email
                ]
            )
          )
        }

        #if date != none {
          align(center)[#block(inset: 1em)[
            #date
          ]]
        }

        #if abstract != none {
          block(inset: 2em)[
          #text(weight: "semibold")[#abstract-title] #h(1em) #abstract
          ]
        }
      ]
    )
  }

  if toc {
    let title = if toc_title == none {
      auto
    } else {
      toc_title
    }
    block(above: 0em, below: 2em)[
    #outline(
      title: title,
      depth: toc_depth,
      indent: toc_indent
    );
    ]
  }

  if lof {
    block(above: 0em, below: 2em)[
    #outline(title: lof-title, target: figure.where(kind: "quarto-float-fig"));
    ]
  }

  if lot {
    block(above: 0em, below: 2em)[
    #outline(title: lot-title, target: figure.where(kind: "quarto-float-tbl"));
    ]
  }

  doc
}

#set table(
  inset: 6pt,
  stroke: none
)
#show heading.where(level: 2): it => block(above: 0.9em, below: 0.4em, text(size: 10pt, fill: rgb("#2c7bb6"), it.body))
#show heading.where(level: 3): it => block(above: 0.7em, below: 0.3em, text(size: 8.5pt, it.body))
#show raw: set text(size: 7pt)
#show table: set text(size: 7.4pt)
#set table(inset: (x: 3pt, y: 2pt), stroke: 0.4pt + luma(200))
#set par(spacing: 0.55em)
#let brand-color = (:)
#let brand-color-background = (:)
#let brand-logo = (:)

#set page(
  paper: "us-letter",
  margin: (x: 1.2cm,y: 1.1cm,),
  numbering: "1",
  columns: 2,
)

#show: doc => article(
  title: [Snakemake cheat sheet],
  subtitle: [Snakemake 8.27.1 · Snakemake for genomics],
  lang: "en",
  region: "US",
  font: ("Libertinus Serif",),
  fontsize: 8pt,
  heading-family: ("Libertinus Serif",),
  sectionnumbering: "none",
  toc_title: [Table of contents],
  toc_depth: 3,
  doc,
)

#block[
= Running
<running>
#table(
  columns: (50%, 50%),
  align: (left,left,),
  table.header([Command], [Does],),
  table.hline(),
  [#NormalTok("snakemake -n");], [dry run: list jobs, run nothing],
  [#NormalTok("snakemake -n -p");], [dry run and print each shell command],
  [#NormalTok("snakemake -c 4");], [run with up to 4 cores (#NormalTok("-c"); is required)],
  [#NormalTok("snakemake -c 4 out/a.bam");], [make one target (file or rule name)],
  [#NormalTok("snakemake -c 4 --keep-going");], [carry on with independent jobs after a failure],
  [#NormalTok("snakemake --until filter");], [run only up to rule #NormalTok("filter"); (and what it needs)],
  [#NormalTok("snakemake --forcerun align");], [rerun #NormalTok("align"); and everything after it],
  [#NormalTok("snakemake -R $(snakemake --list-changes params)");], [rerun outputs whose params changed],
  [#NormalTok("snakemake --rerun-incomplete");], [redo jobs that were killed halfway],
  [#NormalTok("snakemake --unlock");], [remove a stale lock after a crash],
  [#NormalTok("snakemake --touch");], [mark outputs up to date without running],
  [#NormalTok("snakemake --delete-temp-output -n");], [list #NormalTok("temp()"); files that would be removed],
)
= Config and profiles
<config-and-profiles>
#table(
  columns: (50%, 50%),
  align: (left,left,),
  table.header([Command], [Does],),
  table.hline(),
  [#NormalTok("--configfile config/test.yaml");], [load (or overlay) a config file],
  [#NormalTok("--config minMapq=20 outputDir=out2");], [set single config values],
  [#NormalTok("--profile profiles/longleaf");], [options from #NormalTok("profiles/longleaf/config.yaml");],
  [#NormalTok("--sdm conda");], [build and use each rule's #NormalTok("conda:"); env],
  [#NormalTok("-s workflows/RegPipe.snakefile");], [use a Snakefile not named #NormalTok("Snakefile");],
  [#NormalTok("-d /path/to/run");], [run in another working directory],
)
= Looking inside
<looking-inside>
#table(
  columns: (50%, 50%),
  align: (left,left,),
  table.header([Command], [Shows],),
  table.hline(),
  [#NormalTok("--dag \\| dot -Tsvg > dag.svg");], [the graph of jobs],
  [#NormalTok("--rulegraph \\| dot -Tsvg > rules.svg");], [the graph of rules (one box each)],
  [#NormalTok("--list-rules");], [every rule name],
  [#NormalTok("--summary");], [every output: date, rule, status, plan],
  [#NormalTok("--list-changes code");], [outputs whose rule code changed],
  [#NormalTok("--list-changes params");], [outputs whose #NormalTok("params"); changed],
  [#NormalTok("--list-changes input");], [outputs whose input file set changed],
  [#NormalTok("--lint");], [style and correctness suggestions],
  [#NormalTok("--debug-dag");], [why each job was (not) chosen],
  [#NormalTok("--show-failed-logs");], [print the log of a failed job],
)
= Why did it rerun?
<why-did-it-rerun>
A job runs when an output is #strong[missing], #strong[older] than an input, or when its #strong[code], #strong[params], #strong[input set] or #strong[software env] changed (#NormalTok("--rerun-triggers"); picks which count). The #NormalTok("reason:"); line of a dry run says which one. To accept a change without rerunning: #NormalTok("snakemake --touch");.

= A rule
<a-rule>
#Skylighting(([#NormalTok("rule align:");],
[#NormalTok("    ");#BuiltInTok("input");#NormalTok(":");],
[#NormalTok("        fq");#OperatorTok("=");#StringTok("\"data/fastq/");#SpecialCharTok("{sample}");#StringTok(".fastq.gz\"");#NormalTok(",");],
[#NormalTok("        idx");#OperatorTok("=");#StringTok("\"output/index/chr8.1.bt2\"");#NormalTok(",");],
[#NormalTok("    output:");],
[#NormalTok("        temp(");#StringTok("\"output/");#SpecialCharTok("{sample}");#StringTok("/");#SpecialCharTok("{sample}");#StringTok(".unsorted.bam\"");#NormalTok("),");],
[#NormalTok("    params:");],
[#NormalTok("        idx");#OperatorTok("=");#KeywordTok("lambda");#NormalTok(" wc, ");#BuiltInTok("input");#NormalTok(": ");#BuiltInTok("input");#NormalTok(".idx[:");#OperatorTok("-");#DecValTok("6");#NormalTok("],");],
[#NormalTok("    log:");],
[#NormalTok("        ");#CommentTok("\"output/logs/align/{sample}.log\"");#NormalTok(",");],
[#NormalTok("    benchmark:");],
[#NormalTok("        ");#CommentTok("\"output/benchmarks/align/{sample}.tsv\"");],
[#NormalTok("    threads: ");#DecValTok("4");],
[#NormalTok("    resources:");],
[#NormalTok("        mem_mb");#OperatorTok("=");#DecValTok("8000");#NormalTok(", runtime");#OperatorTok("=");#DecValTok("120");#NormalTok(",");],
[#NormalTok("    conda:");],
[#NormalTok("        ");#CommentTok("\"../envs/regpipe_align.yml\"");],
[#NormalTok("    shell:");],
[#NormalTok("        ");#CommentTok("\"bowtie2 -p {threads} -x {params.idx} \"");],
[#NormalTok("        ");#CommentTok("\"-U {input.fq} 2> {log} \"");],
[#NormalTok("        ");#CommentTok("\"| samtools view -b -o {output} -\"");],));
= Directives
<directives>
#table(
  columns: (50%, 50%),
  align: (left,left,),
  table.header([Directive], [Holds],),
  table.hline(),
  [#NormalTok("input:"); / #NormalTok("output:");], [files; named (#NormalTok("fq=");) or positional],
  [#NormalTok("params:");], [non-file values; may use #NormalTok("wildcards");, #NormalTok("config");],
  [#NormalTok("log:");], [per-job log file(s); redirect to #NormalTok("{log}");],
  [#NormalTok("benchmark:");], [per-job time and memory (TSV)],
  [#NormalTok("threads:");], [cores per job, capped by #NormalTok("-c");],
  [#NormalTok("resources:");], [#NormalTok("mem_mb");, #NormalTok("runtime");, #NormalTok("slurm_partition");, …],
  [#NormalTok("conda:");], [env file (relative to the rule file)],
  [#NormalTok("shell:");], [a shell command; #NormalTok("{input}");, #NormalTok("{output}");, …],
  [#NormalTok("run:");], [Python code, with #NormalTok("input");, #NormalTok("output");, … in scope],
  [#NormalTok("script:");], [#NormalTok(".py"); or #NormalTok(".R"); with a #NormalTok("snakemake"); object],
  [#NormalTok("wildcard_constraints:");], [regex per wildcard (rule or global)],
  [#NormalTok("localrules: all, qc_table");], [run these on the head node, not as jobs],
  [#NormalTok("ruleorder: a > b");], [which rule wins when both make a file],
)
= Helpers
<helpers>
#table(
  columns: 2,
  align: (left,left,),
  table.header([Function], [Use],),
  table.hline(),
  [#NormalTok("expand(\"{s}.bam\", s=SAMPLES)");], [list of files from a pattern],
  [#NormalTok("temp(f)");], [delete once no job needs it],
  [#NormalTok("protected(f)");], [write-protect after creation],
  [#NormalTok("directory(\"idx/\")");], [output is a whole folder],
  [#NormalTok("touch(\"x.done\")");], [create an empty sentinel],
  [#NormalTok("ancient(f)");], [ignore this input's time stamp],
  [#NormalTok("multiext(\"idx\", \".1.bt2\", \".2.bt2\")");], [one prefix, many endings],
  [#NormalTok("glob_wildcards(\"data/{s}.fq.gz\").s");], [values found on disk],
)
= Wildcards and input functions
<wildcards-and-input-functions>
#Skylighting(([#NormalTok("SAMPLES ");#OperatorTok("=");#NormalTok(" sheet[");#StringTok("\"sample\"");#NormalTok("].tolist()");],
[],
[#KeywordTok("def");#NormalTok(" control_bam(wc):");],
[#NormalTok("    ctrl ");#OperatorTok("=");#NormalTok(" sheet.loc[wc.sample, ");#StringTok("\"Control\"");#NormalTok("]");],
[#NormalTok("    ");#ControlFlowTok("return");#NormalTok(" [] ");#ControlFlowTok("if");#NormalTok(" ctrl ");#OperatorTok("==");#NormalTok(" ");#StringTok("\"NA\"");#NormalTok(" ");#ControlFlowTok("else");#NormalTok(" ");#SpecialStringTok("f\"output/");#SpecialCharTok("{");#NormalTok("ctrl");#SpecialCharTok("}");#SpecialStringTok("/");#SpecialCharTok("{");#NormalTok("ctrl");#SpecialCharTok("}");#SpecialStringTok(".bam\"");],
[],
[#NormalTok("rule call_peaks:");],
[#NormalTok("    ");#BuiltInTok("input");#NormalTok(":");],
[#NormalTok("        chip");#OperatorTok("=");#StringTok("\"output/");#SpecialCharTok("{sample}");#StringTok("/");#SpecialCharTok("{sample}");#StringTok(".bam\"");#NormalTok(",");],
[#NormalTok("        ctrl");#OperatorTok("=");#NormalTok("control_bam,");],
[#NormalTok("    ...");],));
In #NormalTok("shell:");, double the braces for literal ones: #NormalTok("awk '{{print $1}}'");.

= Config and script
<config-and-script>
#Skylighting(([#CommentTok("# config/RegConfig.yaml");],
[#FunctionTok("samplesheet");#KeywordTok(":");#AttributeTok(" ");#StringTok("\"RegSamplesheet.txt\"");],
[#FunctionTok("minMapq");#KeywordTok(":");#AttributeTok(" ");#DecValTok("30");],));
#Skylighting(([#NormalTok("configfile: ");#StringTok("\"config/RegConfig.yaml\"");],
[#NormalTok("MAPQ ");#OperatorTok("=");#NormalTok(" config[");#StringTok("\"minMapq\"");#NormalTok("]");],));
#Skylighting(([#CommentTok("# scripts/locus_plot.R, called by script:");],
[#NormalTok("bw ");#OtherTok("<-");#NormalTok(" snakemake");#SpecialCharTok("@");#NormalTok("input[[");#StringTok("\"bigwigs\"");#NormalTok("]]");],
[#NormalTok("out ");#OtherTok("<-");#NormalTok(" snakemake");#SpecialCharTok("@");#NormalTok("output[[");#DecValTok("1");#NormalTok("]]");],));
]



