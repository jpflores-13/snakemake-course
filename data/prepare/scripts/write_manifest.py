"""Write data/manifest.tsv (run by the Snakefile through `script:`).

One row per output file: where it came from, the source checksum, the
checksum and size of the file we ship, and the read count for FASTQs.
"""

import gzip
import hashlib
import os
from pathlib import Path

COLUMNS = ["path", "source_accessions", "encode_file", "url", "source_md5",
           "source_md5_from", "output_md5", "read_count", "bytes"]


def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def fastq_reads(path):
    with gzip.open(path, "rb") as fh:
        n = sum(1 for _ in fh)
    if n % 4:
        raise ValueError(f"{path}: {n} lines is not a multiple of 4")
    return n // 4


def main(entries, out):
    with open(out, "w") as fh:
        fh.write("\t".join(COLUMNS) + "\n")
        for e in entries:
            src = e["source_md5"]
            if src.startswith("file:"):
                src = Path(src[5:]).read_text().strip()
            row = {
                **e,
                "source_md5": src,
                "output_md5": md5(e["local"]),
                "read_count": str(fastq_reads(e["local"])) if e.get("fastq") else "NA",
                "bytes": str(os.path.getsize(e["local"])),
            }
            fh.write("\t".join(row[c] for c in COLUMNS) + "\n")


main(snakemake.params.entries, snakemake.output[0])  # noqa: F821
