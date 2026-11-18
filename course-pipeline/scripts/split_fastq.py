"""Split one FASTQ into N chunks for the scatter path (rule split_fastq).

Run by Snakemake's `script:` directive: `snakemake.input`, `snakemake.output` and
`snakemake.log` are filled in by Snakemake. There is one output file per chunk.
Reads are dealt out in turn (read 1 to chunk 1, read 2 to chunk 2, ...), so the
chunks have the same size within one read.
"""
import gzip
import sys

sys.stderr = open(snakemake.log[0], "w")

chunks = [gzip.open(path, "wt", compresslevel=1) for path in snakemake.output]
n_reads = 0
with gzip.open(snakemake.input.fastq, "rt") as fastq:
    while True:
        record = [fastq.readline() for _ in range(4)]   # a FASTQ record is 4 lines
        if not record[0]:
            break
        chunks[n_reads % len(chunks)].writelines(record)
        n_reads += 1
for chunk in chunks:
    chunk.close()

print(f"{n_reads} reads split into {len(chunks)} chunks", file=sys.stderr)
