"""Hard-mask a one-sequence FASTA to N outside a window.

Usage: python mask_reference.py <in.fa.gz> <chrom> <start> <end>
start/end are 1-based and inclusive. Bases inside the window are kept
exactly as UCSC wrote them (lowercase = soft-masked repeats). The sequence
keeps its name and length, so coordinates stay genomic. Writes FASTA with
60 bases per line to stdout.
"""

import gzip
import sys


def main(path, chrom, start, end):
    start, end = int(start), int(end)
    name, chunks = None, []
    with gzip.open(path, "rt") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if line.startswith(">"):
                if name is not None:
                    sys.exit("expected a single sequence in the input FASTA")
                name = line[1:].split()[0]
            else:
                chunks.append(line)
    if name != chrom:
        sys.exit(f"sequence is {name}, expected {chrom}")
    seq = "".join(chunks)
    if not (1 <= start <= end <= len(seq)):
        sys.exit(f"window {start}-{end} is outside 1-{len(seq)}")
    masked = "N" * (start - 1) + seq[start - 1:end] + "N" * (len(seq) - end)
    assert len(masked) == len(seq)
    out = sys.stdout
    out.write(f">{name}\n")
    for i in range(0, len(masked), 60):
        out.write(masked[i:i + 60] + "\n")


if __name__ == "__main__":
    main(*sys.argv[1:])
