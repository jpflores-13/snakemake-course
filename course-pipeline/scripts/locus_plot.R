## Locus figure of the course window (rule locus_plot), drawn with plotgardener.
##
## Run by Snakemake's `script:` directive: the `snakemake` object (an S4 object)
## holds the rule's input, output, params and log, e.g. snakemake@input$bigwigs.
## There are no command-line arguments.
##
## Tracks, top to bottom: one signal track per sample (bigWig, CPM), TT-seq signal per
## replicate and strand, one consensus peak track per target, the ENCODE RAD21 peaks,
## the enhancer / eRNA annotations, the genes, the genome axis. The TT-seq and
## annotation tracks are only drawn when ttseq: is enabled in the config.

## Send messages and warnings to the rule's log file
log <- file(snakemake@log[[1]], open = "wt")
sink(log)
sink(log, type = "message")

suppressPackageStartupMessages({
  library(GenomicRanges)
  library(rtracklayer)
  library(plotgardener)
})

p <- snakemake@params
window <- GRanges(p$chrom, IRanges(p$start, p$end))
samples <- unlist(p$samples)
sample_targets <- unlist(p$sample_targets)
targets <- unlist(p$targets)

## One color per target, from a colorblind-safe palette (Okabe-Ito)
palette <- c("#0072B2", "#D55E00", "#009E73", "#CC79A7", "#E69F00", "#56B4E9")
target_color <- setNames(palette[seq_along(targets)], targets)

## ---- Read the data ------------------------------------------------------
## import(which = ) reads only the window from each bigWig
signals <- lapply(snakemake@input$bigwigs, \(f) import(f, which = window))
names(signals) <- samples

## Same y-axis for all replicates of a target, so they can be compared by eye
target_max <- vapply(targets, \(t) {
  signals[sample_targets == t] |> vapply(\(s) max(s$score, 0), numeric(1)) |> max()
}, numeric(1))

consensus <- lapply(snakemake@input$consensus, \(f) import(f, format = "BED"))
names(consensus) <- targets
## ENCODE peak files are narrowPeak: read as plain BED, their decimal columns fail to parse
rad21 <- import(snakemake@input$rad21, format = "narrowPeak") |> subsetByOverlaps(window)

## Gene models. Default: the assembly's annotation packages (for hg38,
## TxDb.Hsapiens.UCSC.hg38.knownGene and org.Hs.eg.db). plotgardener only finds
## them once they are loaded, so library() them here.
## With a GTF (locusPlot: genesGtf:), build a small TxDb from the window's lines;
## the GTF's gene_id is used as the label, so no org.*.eg.db package is needed.
genes_gtf <- unlist(snakemake@input$genes_gtf)
if (length(genes_gtf) > 0) {
  gtf <- import(genes_gtf, format = "gtf", which = window)
  txdb <- suppressWarnings(txdbmaker::makeTxDbFromGRanges(gtf))
  genes_assembly <- assembly(Genome = p$assembly, TxDb = txdb, OrgDb = NULL,
                             gene.id.column = "GENEID", display.column = "GENEID")
} else {
  ## for another assembly, load its TxDb/OrgDb packages here instead
  stopifnot(p$assembly == "hg38")
  suppressPackageStartupMessages({
    library(TxDb.Hsapiens.UCSC.hg38.knownGene)
    library(org.Hs.eg.db)
  })
  genes_assembly <- p$assembly
}

## TT-seq (optional, config ttseq:): one track per bigWig (replicate x strand), and the
## enhancer / eRNA annotation sets. Empty when ttseq is disabled.
ttseq_tracks <- unlist(p$ttseq_tracks)
ttseq_strands <- unlist(p$ttseq_strands)
ttseq <- lapply(unlist(snakemake@input$ttseq), \(f) import(f, which = window))
names(ttseq) <- ttseq_tracks
## One y-axis per strand: highly transcribed genes (MYC is on the plus strand) would
## otherwise flatten the other strand
ttseq_top <- vapply(ttseq, \(s) max(s$score, 0), numeric(1))
strand_max <- tapply(ttseq_top, ttseq_strands, max)
annotations <- lapply(unlist(snakemake@input$annotations), \(f) import(f, format = "gtf"))
names(annotations) <- unlist(p$annotation_names)

message("Signal tracks: ", length(signals), "; consensus peaks: ",
        paste(names(consensus), lengths(consensus), sep = "=", collapse = ", "),
        "; RAD21 peaks in window: ", length(rad21))

## ---- Page layout (inches) ------------------------------------------------
x0 <- 1.3              # left margin: room for track labels
width <- 5.9
signal_h <- 0.45
peak_h <- 0.15
gap <- 0.08
n_tracks <- length(signals) + length(ttseq) + length(consensus) + length(annotations) + 1
page_h <- 0.6 + n_tracks * (signal_h + gap) + 1.6

pdf(snakemake@output$pdf, width = 7.5, height = page_h)
pageCreate(width = 7.5, height = page_h, default.units = "inches", showGuides = FALSE)

region <- pgParams(chrom = p$chrom, chromstart = p$start, chromend = p$end,
                   assembly = genes_assembly, x = x0, width = width, just = c("left", "top"),
                   default.units = "inches")

plotText(label = paste0(p$title, " locus, ", p$chrom, ":",
                        format(p$start, big.mark = ","), "-", format(p$end, big.mark = ",")),
         x = 3.75, y = 0.25, just = "center", fontsize = 11, fontface = "bold",
         default.units = "inches")

y <- 0.55
label <- function(text, y, h, color = "black") {
  plotText(label = text, x = x0 - 0.1, y = y + h / 2, just = "right", fontsize = 7,
           fontcolor = color, default.units = "inches")
}

## ---- Signal tracks -------------------------------------------------------
for (s in samples) {
  t <- sample_targets[samples == s]
  track <- plotSignal(data = signals[[s]], params = region, y = y, height = signal_h,
                      range = c(0, target_max[[t]]), fill = target_color[[t]],
                      linecolor = target_color[[t]])
  annoYaxis(plot = track, at = c(0, round(target_max[[t]], 1)), fontsize = 5)
  label(s, y, signal_h, target_color[[t]])
  y <- y + signal_h + gap
}

## ---- TT-seq tracks: plus strand in red, minus strand in blue --------------------------
strand_color <- c(plus = "#B2182B", minus = "#2166AC")
for (i in seq_along(ttseq)) {
  top <- strand_max[[ttseq_strands[i]]]
  track <- plotSignal(data = ttseq[[i]], params = region, y = y, height = signal_h,
                      range = c(0, top), fill = strand_color[[ttseq_strands[i]]],
                      linecolor = strand_color[[ttseq_strands[i]]])
  annoYaxis(plot = track, at = c(0, round(top)), fontsize = 5)
  label(ttseq_tracks[i], y, signal_h, strand_color[[ttseq_strands[i]]])
  y <- y + signal_h + gap
}

## ---- Peak tracks ------------------------------------------------------------
for (t in targets) {
  plotRanges(data = consensus[[t]], params = region, y = y, height = peak_h,
             fill = target_color[[t]], linecolor = NA, collapse = TRUE)
  label(paste(t, "consensus"), y, peak_h, target_color[[t]])
  y <- y + peak_h + gap
}
plotRanges(data = rad21, params = region, y = y, height = peak_h,
           fill = "grey30", linecolor = NA, collapse = TRUE)
label("RAD21 (ENCODE)", y, peak_h)
y <- y + peak_h + gap
for (a in names(annotations)) {
  plotRanges(data = annotations[[a]], params = region, y = y, height = peak_h,
             fill = "#E69F00", linecolor = NA, collapse = TRUE)
  label(paste(a, "(TT-seq)"), y, peak_h)
  y <- y + peak_h + gap
}
y <- y + gap

## ---- Genes and axis ---------------------------------------------------------
## plotGenes takes gene models from the assembly's TxDb and gene names from org.Hs.eg.db
plotGenes(params = region, y = y, height = 0.9, fontsize = 6)
y <- y + 0.9 + gap
plotGenomeLabel(params = region, y = y, length = width, scale = "Mb", fontsize = 7)

invisible(dev.off())
message("Wrote ", snakemake@output$pdf)
