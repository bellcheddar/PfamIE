"""
PfamIE Data Forge: Stockholm seed parsing and Pfam flatfile readers.

Everything here is offline: it reads the Pfam FTP release files that
`fetch_raw.sh` downloads, so the forge does not depend on the InterPro API
for any of the core family metadata.
"""

from __future__ import annotations

import gzip
import hashlib
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterator

# A seed sequence name looks like  Q9UJX3_HUMAN/12-238  or  A0A0A0MRZ7_9SPHI/23-146
SEQ_NAME_RE = re.compile(r"^(?P<name>\S+?)/(?P<start>\d+)-(?P<end>\d+)$")

# Residues we keep. Anything else in a seed alignment (gaps, dots, lower case
# insert columns in some releases) is stripped before embedding.
AA_KEEP = set("ACDEFGHIKLMNPQRSTVWY")

DUF_PHRASES = (
    "unknown function",
    "uncharacterised protein",
    "uncharacterized protein",
    "function is unknown",
    "no known function",
)


@dataclass
class SeedSequence:
    """One row of a seed alignment, with its UniProt provenance."""

    name: str            # e.g. Q9UJX3_HUMAN/12-238
    uniprot: str | None  # e.g. Q9UJX3, from the #=GS ... AC line
    start: int
    end: int
    sequence: str        # ungapped, upper case, non-standard residues removed

    @property
    def length(self) -> int:
        return len(self.sequence)


@dataclass
class Family:
    """A Pfam-A family as read from the seed alignment."""

    accession: str                  # PF00069 (version stripped)
    version: str                    # PF00069.31
    identifier: str                 # Pkinase
    description: str                # one-line DE
    entry_type: str                 # Domain / Family / Repeat / Motif / Coiled-coil / Disordered
    clan: str | None                # CL0016
    abstract: str                   # joined CC block, citations stripped
    seed_count: int
    sequences: list[SeedSequence] = field(default_factory=list)

    @property
    def is_duf(self) -> bool:
        if self.identifier.upper().startswith("DUF"):
            return True
        haystack = f"{self.description} {self.abstract}".lower()
        return any(p in haystack for p in DUF_PHRASES)


def _clean_abstract(lines: list[str]) -> str:
    """Join a #=GF CC block into one paragraph and strip Pfam citation markup."""
    text = " ".join(line.strip() for line in lines)
    text = re.sub(r"\[\s*\d+(\s*,\s*\d+)*\s*\]", "", text)      # [1], [1,2]
    text = re.sub(r"\[\[cite:[^\]]+\]\]", "", text)             # [[cite:PUB…]]
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def iter_seed_families(seed_gz: Path, max_seqs: int = 64) -> Iterator[Family]:
    """
    Stream Pfam-A.seed.gz, yielding one Family per Stockholm record.

    `max_seqs` caps how many alignment rows are retained per family. The forge
    only ever needs a handful of representatives, and some seeds run to
    thousands of rows, so keeping them all would cost gigabytes for nothing.
    """
    with gzip.open(seed_gz, "rt", encoding="latin-1") as handle:
        gf: dict[str, list[str]] = {}
        gs_acc: dict[str, str] = {}
        rows: dict[str, list[str]] = {}
        order: list[str] = []
        row_total = 0

        for raw in handle:
            line = raw.rstrip("\n")

            if line.startswith("//"):
                fam = _build_family(gf, gs_acc, rows, order, row_total)
                if fam is not None:
                    yield fam
                gf, gs_acc, rows, order, row_total = {}, {}, {}, [], 0
                continue

            if not line or line.startswith("# STOCKHOLM"):
                continue

            if line.startswith("#=GF "):
                parts = line[5:].split(None, 1)
                if len(parts) == 2:
                    gf.setdefault(parts[0], []).append(parts[1])
                continue

            if line.startswith("#=GS "):
                parts = line[5:].split()
                if len(parts) >= 3 and parts[1] == "AC":
                    gs_acc[parts[0]] = parts[2].split(".")[0]
                continue

            if line.startswith("#"):
                continue

            parts = line.split(None, 1)
            if len(parts) != 2:
                continue
            name, chunk = parts
            row_total += 1 if name not in rows else 0
            if name not in rows:
                if len(order) >= max_seqs:
                    continue
                order.append(name)
                rows[name] = []
            rows[name].append(chunk)

        # A well-formed file ends with '//', but never rely on it.
        fam = _build_family(gf, gs_acc, rows, order, row_total)
        if fam is not None:
            yield fam


def _build_family(gf, gs_acc, rows, order, row_total) -> Family | None:
    if "AC" not in gf:
        return None

    version = gf["AC"][0].strip()
    accession = version.split(".")[0]

    sequences: list[SeedSequence] = []
    for name in order:
        aligned = "".join(rows[name]).upper()
        seq = "".join(c for c in aligned if c in AA_KEEP)
        if len(seq) < 20:                       # fragments help nobody
            continue
        m = SEQ_NAME_RE.match(name)
        start, end = (int(m["start"]), int(m["end"])) if m else (1, len(seq))
        sequences.append(
            SeedSequence(
                name=name,
                uniprot=gs_acc.get(name),
                start=start,
                end=end,
                sequence=seq,
            )
        )

    return Family(
        accession=accession,
        version=version,
        identifier=gf.get("ID", [accession])[0].strip(),
        description=gf.get("DE", [""])[0].strip(),
        entry_type=gf.get("TP", ["Family"])[0].strip(),
        clan=gf["CL"][0].strip() if "CL" in gf else None,
        abstract=_clean_abstract(gf.get("CC", [])),
        seed_count=row_total,
        sequences=sequences,
    )


def read_clan_names(pfam_c_gz: Path) -> dict[str, dict]:
    """
    Parse Pfam-C.gz (Stockholm) into {CL0016: {id, description, members}}.
    """
    clans: dict[str, dict] = {}
    with gzip.open(pfam_c_gz, "rt", encoding="latin-1") as handle:
        cur: dict = {"members": []}
        for raw in handle:
            line = raw.rstrip("\n")
            if line.startswith("//"):
                acc = cur.get("accession")
                if acc:
                    clans[acc] = cur
                cur = {"members": []}
                continue
            if not line.startswith("#=GF "):
                continue
            parts = line[5:].split(None, 1)
            if len(parts) != 2:
                continue
            tag, value = parts[0], parts[1].strip()
            if tag == "AC":
                cur["accession"] = value.split(".")[0]
            elif tag == "ID":
                cur["identifier"] = value
            elif tag == "DE":
                cur["description"] = value
            elif tag == "MB":
                cur["members"].extend(
                    v.split(".")[0] for v in value.rstrip(";").split(";") if v.strip()
                )
            elif tag == "CC":
                cur["abstract"] = (cur.get("abstract", "") + " " + value).strip()
    return clans


def clan_hue(clan_acc: str | None) -> float:
    """
    Stable hue in [0, 1) for a clan accession, so Galaxy colours never shuffle
    between forge runs. Unclanned families get a fixed neutral hue.
    """
    if not clan_acc:
        return -1.0
    digest = hashlib.sha1(clan_acc.encode()).digest()
    return int.from_bytes(digest[:4], "big") / 2**32
