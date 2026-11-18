# Join the per-strand tables into one table per replicate (plus and minus
# columns), and stack the replicates into one combined table.
# Called by the ttseq_tables rule. Input order comes from expand():
# rep1_plus, rep1_minus, rep2_plus, rep2_minus.

log <- file(snakemake@log[[1]], open = "wt")
sink(log, type = "message")

reps    <- unlist(snakemake@params$reps)
strands <- unlist(snakemake@params$strands)
inputs  <- matrix(unlist(snakemake@input), nrow = length(strands),
                  dimnames = list(strands, reps))

read_tsv <- \(f) read.delim(f, check.names = FALSE)

all_reps <- list()
for (i in seq_along(reps)) {
  per_strand <- lapply(strands, \(s) read_tsv(inputs[s, reps[i]]))
  tab <- per_strand[[1]][, c("enhancer", "chrom", "start", "end")]
  for (j in seq_along(strands)) {
    tab[[strands[j]]] <- per_strand[[j]]$signal
  }
  write.table(tab, snakemake@output$reps[[i]],
              sep = "\t", quote = FALSE, row.names = FALSE)
  all_reps[[i]] <- cbind(rep = reps[i], tab)
}

do.call(rbind, all_reps) |>
  write.table(snakemake@output$combined, sep = "\t", quote = FALSE, row.names = FALSE)
