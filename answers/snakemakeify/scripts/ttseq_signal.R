# Mean TT-seq coverage over each enhancer, for one replicate and one strand.
# Called by the ttseq_signal rule: one bigWig in, one TSV out.

log <- file(snakemake@log[[1]], open = "wt")
sink(log, type = "message")

suppressPackageStartupMessages({
  library(GenomicRanges)
  library(rtracklayer)
})

enhancers <- import(snakemake@input$enhancers)
cov <- import(snakemake@input$bigwig, as = "RleList")

# one Views per chromosome, so this works for any chromosome in the GTF
means <- numeric(length(enhancers))
for (chrom in unique(as.character(seqnames(enhancers)))) {
  idx <- which(seqnames(enhancers) == chrom)
  means[idx] <- Views(cov[[chrom]], ranges(enhancers[idx])) |>
    viewMeans() |>
    round(4)
}

data.frame(enhancer = enhancers$ID,
           chrom = as.character(seqnames(enhancers)),
           start = start(enhancers),
           end = end(enhancers),
           signal = means) |>
  write.table(snakemake@output[[1]], sep = "\t", quote = FALSE, row.names = FALSE)
