# MYC locus figure: CPM tracks for every sample plus the consensus peaks,
# and a table of the CTCF consensus peaks in the window with RAD21 status.
# Called by the locus_plot rule with script:, so every path and the region
# come from the rule (snakemake@input, snakemake@params, snakemake@output).

log <- file(snakemake@log[[1]], open = "wt")
sink(log, type = "message")

suppressPackageStartupMessages({
  library(GenomicRanges)
  library(rtracklayer)
})

p <- snakemake@params
region <- GRanges(p$chrom, IRanges(p$start, p$end))

bigwigs   <- setNames(unlist(snakemake@input$bigwigs), unlist(p$track_names))
consensus <- setNames(unlist(snakemake@input$consensus), unlist(p$peak_names))

# narrowPeak/BED -> GRanges (only the first three columns are needed)
read_peaks <- function(path) {
  df <- read.table(path, sep = "\t")[, 1:3]
  GRanges(df[[1]], IRanges(df[[2]] + 1, df[[3]]))
}

signal <- lapply(bigwigs, \(f) import(f, which = region))
peaks  <- lapply(consensus, read_peaks) |> lapply(subsetByOverlaps, region)
rad21  <- read_peaks(snakemake@input$rad21) |> subsetByOverlaps(ranges = region)

pdf(snakemake@output$pdf, width = 8, height = 10)
layout(matrix(seq_len(length(signal) + 1)), heights = c(rep(1, length(signal)), 1.2))
par(mar = c(1, 5, 1, 1), oma = c(3, 0, 1, 0))
for (name in names(signal)) {
  gr <- signal[[name]]
  plot(start(gr), gr$score, type = "h", col = "grey30", xaxt = "n",
       xlim = c(start(region), end(region)), xlab = "", ylab = name, las = 1)
}
peak_sets <- c(peaks, list(RAD21 = rad21))
plot(NULL, xlim = c(start(region), end(region)), ylim = c(0.5, length(peak_sets) + 0.5),
     yaxt = "n", xlab = "", ylab = "")
axis(2, at = seq_along(peak_sets), labels = names(peak_sets), las = 1)
for (i in seq_along(peak_sets)) {
  gr <- peak_sets[[i]]
  rect(start(gr), i - 0.3, end(gr), i + 0.3, col = "black", border = NA)
}
mtext(paste(p$chrom, "position (hg38)"), side = 1, line = 2.5)
invisible(dev.off())

ctcf <- peaks$CTCF
ctcf$with_RAD21 <- ctcf %over% rad21
write.table(as.data.frame(ctcf)[, c("seqnames", "start", "end", "with_RAD21")],
            snakemake@output$tsv, sep = "\t", quote = FALSE, row.names = FALSE)
