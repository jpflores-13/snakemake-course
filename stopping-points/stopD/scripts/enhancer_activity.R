## TT-seq signal over published enhancers and eRNAs (rule enhancer_activity).
##
## Run by Snakemake's `script:` directive: the `snakemake` object holds the rule's
## input, output, params and log (snakemake@input$ttseq, snakemake@params$..., ...).
##
## One output row per enhancer / eRNA in the window:
##   set, id, chrom, start, end, strand      the feature (1-based, inclusive)
##   ttseq_<replicate>_<strand>              mean TT-seq signal over the feature
##   overlaps_<target>                       TRUE if a consensus peak of that target overlaps it
##   overlaps_RAD21_ENCODE                   TRUE if an ENCODE RAD21 peak overlaps it
## "Overlaps" means at least 1 bp in common.

## Send messages and warnings to the rule's log file
log <- file(snakemake@log[[1]], open = "wt")
sink(log)
sink(log, type = "message")

suppressPackageStartupMessages({
  library(GenomicRanges)
  library(rtracklayer)
})

p <- snakemake@params
window <- GRanges(p$chrom, IRanges(p$start, p$end))

## ---- Features: every annotation set, window only ------------------------------
## GTF lines from GEO: the feature name is in the ID attribute
features <- Map(\(path, set) {
  gtf <- import(path, format = "gtf") |> subsetByOverlaps(window, type = "within")
  gtf$set <- set
  gtf$id <- gtf$ID
  gtf[, c("set", "id")]
}, unlist(snakemake@input$annotations), unlist(p$annotation_names)) |>
  unname() |>
  GRangesList() |>
  unlist()
message("Features in the window: ", paste(names(table(features$set)), table(features$set),
                                          sep = "=", collapse = ", "))

## ---- TT-seq: mean signal over each feature, per bigWig ------------------------
## as = "RleList" gives per-base coverage; [features] cuts out each feature; mean() averages it.
## Bases a bigWig does not cover count as 0.
for (i in seq_along(p$ttseq_tracks)) {
  coverage <- import(snakemake@input$ttseq[[i]], which = window, as = "RleList")
  signal <- coverage[features] |> mean()
  mcols(features)[[paste0("ttseq_", p$ttseq_tracks[[i]])]] <- round(signal, 3)
}

## ---- Overlaps with peaks -------------------------------------------------------
for (i in seq_along(p$overlap_targets)) {
  peaks <- import(snakemake@input$consensus[[i]], format = "BED")
  mcols(features)[[paste0("overlaps_", p$overlap_targets[[i]])]] <- overlapsAny(features, peaks, ignore.strand = TRUE)
}
## ENCODE peak files are narrowPeak: read as plain BED, their decimal columns fail to parse
rad21 <- import(snakemake@input$rad21, format = "narrowPeak")
features$overlaps_RAD21_ENCODE <- overlapsAny(features, rad21, ignore.strand = TRUE)

## ---- Write the table -------------------------------------------------------------
table_out <- data.frame(chrom = as.character(seqnames(features)), start = start(features),
                        end = end(features), strand = as.character(strand(features)),
                        mcols(features), check.names = FALSE)
table_out <- table_out[, c("set", "id", "chrom", "start", "end", "strand",
                           setdiff(colnames(table_out), c("set", "id", "chrom", "start", "end", "strand")))]
write.table(table_out, snakemake@output$tsv, sep = "\t", quote = FALSE, row.names = FALSE)

overlap_cols <- grep("^overlaps_", colnames(table_out), value = TRUE)
for (s in unique(table_out$set)) {
  rows <- table_out$set == s
  message(s, ": ", sum(rows), " features; overlapping ",
          paste(sub("overlaps_", "", overlap_cols), colSums(table_out[rows, overlap_cols]),
                sep = "=", collapse = ", "))
}
