"""
PfamIE Data Forge, stage 1: family metadata and representative sequence choice.

Reads the Pfam release flatfiles and writes build/families.json.gz, which every
later stage consumes. No network access.
"""

from __future__ import annotations

import gzip
import json
import re
from pathlib import Path

from pfam_parse import clan_hue, iter_seed_families, read_clan_names

# Organisms whose entries tend to be reviewed and well studied. Used only to
# break ties when choosing the family's structural representative.
PREFERRED_ORGANISMS = (
    "HUMAN", "MOUSE", "RAT", "YEAST", "ECOLI", "BACSU", "DROME",
    "ARATH", "CAEEL", "DANRE", "CHICK", "BOVIN", "PIG", "XENLA",
)

# Swiss-Prot accessions are six characters (P12931); TrEMBL ones are usually ten
# (A0A0A0MRZ7). Six is a decent offline proxy for "reviewed".
SWISSPROT_RE = re.compile(r"^[OPQ][0-9][A-Z0-9]{3}[0-9]$|^[A-NR-Z][0-9][A-Z][A-Z0-9]{2}[0-9]$")

N_CENTROID_SEQS = 3      # sequences averaged into the family centroid
N_HELDOUT_SEQS = 1       # sequences kept back to calibrate confidence
MIN_LEN, MAX_LEN = 20, 1022   # ESM-2 takes 1024 tokens including BOS/EOS


def _representative_score(seq, median_len: int) -> tuple:
    """Rank a seed sequence as the family's structural representative."""
    organism = seq.name.rsplit("/", 1)[0].split("_")[-1]
    return (
        0 if seq.uniprot else 1,
        0 if organism in PREFERRED_ORGANISMS else 1,
        0 if seq.uniprot and SWISSPROT_RE.match(seq.uniprot) else 1,
        abs(seq.length - median_len),
    )


def _pick_sequences(family) -> tuple[list, list, dict | None]:
    """
    Choose the centroid sequences, the held-out sequences and the structural
    representative for one family.

    Centroid sequences are the ones closest to the median seed length: seed
    alignments contain fragments and outsized multi-domain rows, and averaging
    those into a centroid blurs the family.
    """
    usable = [s for s in family.sequences if MIN_LEN <= s.length <= MAX_LEN]
    if not usable:
        # Fall back to truncating over-long rows rather than dropping the family.
        usable = [s for s in family.sequences if s.length >= MIN_LEN]
        for s in usable:
            s.sequence = s.sequence[:MAX_LEN]
    if not usable:
        return [], [], None

    lengths = sorted(s.length for s in usable)
    median_len = lengths[len(lengths) // 2]
    by_typicality = sorted(usable, key=lambda s: (abs(s.length - median_len), s.name))

    centroid = by_typicality[:N_CENTROID_SEQS]
    heldout = by_typicality[N_CENTROID_SEQS : N_CENTROID_SEQS + N_HELDOUT_SEQS]

    rep = min(usable, key=lambda s: _representative_score(s, median_len))
    representative = (
        {
            "uniprot": rep.uniprot,
            "start": rep.start,
            "end": rep.end,
            "name": rep.name,
            "length": rep.length,
        }
        if rep.uniprot
        else None
    )
    return centroid, heldout, representative


def run(raw_dir: Path, build_dir: Path) -> dict:
    clans = read_clan_names(raw_dir / "Pfam-C.gz")
    build_dir.mkdir(parents=True, exist_ok=True)

    families: list[dict] = []
    skipped: list[str] = []

    for fam in iter_seed_families(raw_dir / "Pfam-A.seed.gz"):
        centroid, heldout, representative = _pick_sequences(fam)
        if not centroid:
            skipped.append(fam.accession)
            continue

        clan_meta = clans.get(fam.clan or "", {})
        families.append(
            {
                "accession": fam.accession,
                "version": fam.version,
                "identifier": fam.identifier,
                "description": fam.description,
                "abstract": fam.abstract,
                "type": fam.entry_type,
                "clan": fam.clan,
                "clan_id": clan_meta.get("identifier"),
                "clan_description": clan_meta.get("description"),
                "clan_hue": clan_hue(fam.clan),
                "is_duf": fam.is_duf,
                "seed_count": fam.seed_count,
                "representative": representative,
                "centroid_seqs": [
                    {"name": s.name, "uniprot": s.uniprot, "start": s.start,
                     "end": s.end, "sequence": s.sequence}
                    for s in centroid
                ],
                "heldout_seqs": [
                    {"name": s.name, "uniprot": s.uniprot, "start": s.start,
                     "end": s.end, "sequence": s.sequence}
                    for s in heldout
                ],
            }
        )

    families.sort(key=lambda f: f["accession"])
    out = build_dir / "families.json.gz"
    with gzip.open(out, "wt", encoding="utf-8") as fh:
        json.dump(families, fh)

    stats = {
        "families": len(families),
        "skipped": len(skipped),
        "with_clan": sum(1 for f in families if f["clan"]),
        "clans": len({f["clan"] for f in families if f["clan"]}),
        "dufs": sum(1 for f in families if f["is_duf"]),
        "with_representative": sum(1 for f in families if f["representative"]),
        "with_abstract": sum(1 for f in families if len(f["abstract"]) > 40),
        "with_heldout": sum(1 for f in families if f["heldout_seqs"]),
        "centroid_sequences": sum(len(f["centroid_seqs"]) for f in families),
        "output": str(out),
        "output_mb": round(out.stat().st_size / 1e6, 2),
    }
    (build_dir / "stage_metadata.json").write_text(json.dumps(stats, indent=2))
    return stats


if __name__ == "__main__":
    import sys
    root = Path(__file__).resolve().parent.parent
    print(json.dumps(run(root / "assets/raw", root / "assets/build"), indent=2))
