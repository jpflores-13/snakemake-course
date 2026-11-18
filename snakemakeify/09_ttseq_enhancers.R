# TT-seq signal over the published HCT116 enhancers (GSE152291), both strands,
# for each replicate. Enhancers are transcribed in both directions, so we
# want the mean coverage on the plus and on the minus strand of each one.
# Uses the GEO files in data/geo, nothing from 01-08.
#   Rscript 09_ttseq_enhancers.R
# Writes ttseq_enhancers_rep1.tsv, ttseq_enhancers_rep2.tsv, ttseq_enhancers_all.tsv

suppressPackageStartupMessages({
  library(GenomicRanges)
  library(rtracklayer)
})

geo <- "~/snakemake-course/data/geo"

enhancers <- import(file.path(geo, "TTseq_HCT116_enhancers.gtf.gz"))

all_reps <- list()
for (rep in c(1, 2)) {
  tab <- data.frame(enhancer = enhancers$ID,
                    chrom = as.character(seqnames(enhancers)),
                    start = start(enhancers),
                    end = end(enhancers))

  for (strand in c("plus", "minus")) {
    bw <- file.path(geo, paste0("TTseq_HCT116_", rep, "_", strand, ".bw"))
    cov <- import(bw, as = "RleList")
    tab[[strand]] <- Views(cov[["chr8"]], ranges(enhancers)) |>
      viewMeans() |>
      round(4)
  }

  write.table(tab, paste0("ttseq_enhancers_rep", rep, ".tsv"),
              sep = "\t", quote = FALSE, row.names = FALSE)
  all_reps[[rep]] <- cbind(rep = rep, tab)
}

combined <- do.call(rbind, all_reps)
write.table(combined, "ttseq_enhancers_all.tsv",
            sep = "\t", quote = FALSE, row.names = FALSE)

cat("enhancers:", length(enhancers), "\n")
