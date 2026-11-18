# MYC locus figure: CPM tracks for every sample plus the consensus peaks,
# and a table of the CTCF consensus peaks in the window with RAD21 status.
# Run from the analysis folder after 03_filter.sh and 07_overlap.sh:
#   Rscript 08_locus_plot.R
# Writes MYC_locus.pdf and MYC_locus_CTCF_peaks.tsv

suppressPackageStartupMessages({
  library(GenomicRanges)
  library(rtracklayer)
})

region <- GRanges("chr8", IRanges(127300000, 127800000))

bigwigs <- c(
  CTCF_1    = "tracks/HCT116_CTCF_1.bw",
  CTCF_2    = "tracks/HCT116_CTCF_2.bw",
  H3K27ac_1 = "tracks/HCT116_H3K27ac_1.bw",
  H3K27ac_2 = "tracks/HCT116_H3K27ac_2.bw",
  DNase_1   = "tracks/HCT116_DNase_1.bw",
  DNase_2   = "tracks/HCT116_DNase_2.bw"
)
consensus <- c(
  CTCF    = "overlap/CTCF_consensus.bed",
  H3K27ac = "overlap/H3K27ac_consensus.bed",
  DNase   = "overlap/DNase_consensus.bed"
)
rad21_file <- "~/snakemake-course/data/peaks/RAD21_ENCFF391AAM.bed.gz"

# narrowPeak/BED -> GRanges (only the first three columns are needed)
read_peaks <- function(path) {
  df <- read.table(path, sep = "\t")[, 1:3]
  GRanges(df[[1]], IRanges(df[[2]] + 1, df[[3]]))
}

signal <- lapply(bigwigs, \(f) import(f, which = region))
peaks  <- lapply(consensus, read_peaks) |> lapply(subsetByOverlaps, region)
rad21  <- read_peaks(rad21_file) |> subsetByOverlaps(ranges = region)

pdf("MYC_locus.pdf", width = 8, height = 10)
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
mtext("chr8 position (hg38)", side = 1, line = 2.5)
dev.off()

ctcf <- peaks$CTCF
ctcf$with_RAD21 <- ctcf %over% rad21
write.table(as.data.frame(ctcf)[, c("seqnames", "start", "end", "with_RAD21")],
            "MYC_locus_CTCF_peaks.tsv", sep = "\t", quote = FALSE, row.names = FALSE)
