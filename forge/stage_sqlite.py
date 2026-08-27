"""
PfamIE Data Forge, stage 9: pfam.sqlite.

One file carrying every non-vector fact the app needs: families, clans, domain
architectures, co-occurrence edges and a full-text index. Row ids are dense and
0-based so that `family.rowid` indexes directly into centroids.bin, umap3d.bin
and desc_emb.bin. Nothing in the app ever maps an accession to a vector by
searching; it is always the same integer.
"""

from __future__ import annotations

import gzip
import json
import sqlite3
from collections import defaultdict
from pathlib import Path

import numpy as np

SCHEMA = """
PRAGMA journal_mode = OFF;
PRAGMA page_size = 4096;

CREATE TABLE family (
    row             INTEGER PRIMARY KEY,   -- 0-based, matches every .bin file
    accession       TEXT NOT NULL UNIQUE,
    version         TEXT,
    identifier      TEXT NOT NULL,
    description     TEXT,
    abstract        TEXT,
    type            TEXT,
    clan            TEXT,
    is_duf          INTEGER NOT NULL DEFAULT 0,
    seed_count      INTEGER,
    n_proteins      INTEGER,
    n_taxa          INTEGER,
    n_structures    INTEGER,
    n_architectures INTEGER,
    rep_uniprot     TEXT,
    rep_start       INTEGER,
    rep_end         INTEGER,
    rep_length      INTEGER,
    x               REAL,
    y               REAL,
    z               REAL
);

CREATE TABLE clan (
    accession   TEXT PRIMARY KEY,
    identifier  TEXT,
    description TEXT,
    hue         REAL,
    n_families  INTEGER
);

CREATE TABLE architecture (
    id          INTEGER PRIMARY KEY,
    signature   TEXT NOT NULL UNIQUE,   -- 'PF00018-PF00017-PF07714', N to C
    n_domains   INTEGER NOT NULL,
    n_proteins  INTEGER NOT NULL,
    rep_uniprot TEXT,
    rep_length  INTEGER
);

CREATE TABLE architecture_member (
    architecture_id INTEGER NOT NULL,
    position        INTEGER NOT NULL,   -- 0-based, N to C
    family_row      INTEGER NOT NULL
);

CREATE TABLE family_architecture (
    family_row      INTEGER NOT NULL,
    architecture_id INTEGER NOT NULL,
    n_proteins      INTEGER NOT NULL,
    rank            INTEGER NOT NULL    -- 0 = this family's commonest context
);

CREATE TABLE cooccurrence (
    family_row  INTEGER NOT NULL,
    partner_row INTEGER NOT NULL,
    n_proteins  INTEGER NOT NULL,       -- proteins carrying both
    n_before    INTEGER NOT NULL,       -- partner N-terminal to this family
    n_after     INTEGER NOT NULL
);

CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
"""

INDEXES = """
CREATE INDEX idx_family_clan       ON family(clan);
CREATE INDEX idx_family_duf        ON family(is_duf, n_proteins DESC);
CREATE INDEX idx_family_size       ON family(n_proteins DESC);
CREATE INDEX idx_family_identifier ON family(identifier);
CREATE INDEX idx_arch_member_arch  ON architecture_member(architecture_id, position);
CREATE INDEX idx_arch_member_fam   ON architecture_member(family_row);
CREATE INDEX idx_fam_arch          ON family_architecture(family_row, rank);
CREATE INDEX idx_arch_size         ON architecture(n_proteins DESC);
CREATE INDEX idx_cooc              ON cooccurrence(family_row, n_proteins DESC);
"""

# External-content FTS: the index points at `family` rather than copying the
# abstracts, which would roughly double the file for no benefit.
FTS = """
CREATE VIRTUAL TABLE family_fts USING fts5(
    accession, identifier, description, abstract,
    content='family', content_rowid='row', tokenize='porter unicode61'
);
INSERT INTO family_fts(rowid, accession, identifier, description, abstract)
    SELECT row, accession, identifier, description, abstract FROM family;
INSERT INTO family_fts(family_fts) VALUES('optimize');
"""

MAX_COOCCURRENCE_PARTNERS = 24     # per family, the strongest edges only


def _load_counters(build_dir: Path) -> dict[str, dict]:
    out: dict[str, dict] = {}
    path = build_dir / "counters.jsonl"
    if not path.exists():
        return out
    with path.open() as fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except Exception:
                continue
            out[rec["accession"]] = rec
    return out


def _load_ida(build_dir: Path) -> dict[str, dict]:
    out: dict[str, dict] = {}
    path = build_dir / "ida.jsonl"
    if not path.exists():
        return out
    with path.open() as fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except Exception:
                continue           # a torn final line from an interrupted fetch
            out[rec["accession"]] = rec
    return out


def run(build_dir: Path, out_path: Path) -> dict:
    families = json.loads(
        gzip.open(build_dir / "families.json.gz", "rt", encoding="utf-8").read()
    )
    coords = np.load(build_dir / "umap3d.npy")
    counters = _load_counters(build_dir)
    ida = _load_ida(build_dir)

    row_of = {f["accession"]: i for i, f in enumerate(families)}

    if out_path.exists():
        out_path.unlink()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(out_path)
    db.executescript(SCHEMA)

    # ---- families -------------------------------------------------------
    rows = []
    for i, f in enumerate(families):
        c = counters.get(f["accession"], {})
        rep = f["representative"] or {}
        rows.append((
            i, f["accession"], f["version"], f["identifier"], f["description"],
            f["abstract"], f["type"], f["clan"], int(f["is_duf"]), f["seed_count"],
            c.get("proteins", 0), c.get("taxa", 0), c.get("structures", 0),
            c.get("architectures", 0),
            rep.get("uniprot"), rep.get("start"), rep.get("end"), rep.get("length"),
            float(coords[i, 0]), float(coords[i, 1]), float(coords[i, 2]),
        ))
    db.executemany(
        "INSERT INTO family VALUES (" + ",".join("?" * 21) + ")", rows
    )

    # ---- clans ----------------------------------------------------------
    clan_rows: dict[str, list] = {}
    clan_counts: dict[str, int] = defaultdict(int)
    for f in families:
        if f["clan"]:
            clan_counts[f["clan"]] += 1
            clan_rows.setdefault(
                f["clan"],
                [f["clan"], f["clan_id"], f["clan_description"], f["clan_hue"], 0],
            )
    for acc, row in clan_rows.items():
        row[4] = clan_counts[acc]
    db.executemany("INSERT INTO clan VALUES (?,?,?,?,?)", list(clan_rows.values()))

    # ---- architectures --------------------------------------------------
    # One row per distinct N-to-C signature, shared by every family in it.
    arch_id: dict[str, int] = {}
    arch_rows: list[tuple] = []
    member_rows: list[tuple] = []
    fam_arch_rows: list[tuple] = []
    cooc: dict[tuple[int, int], list[int]] = defaultdict(lambda: [0, 0, 0])

    for acc, rec in ida.items():
        home = row_of.get(acc)
        if home is None:
            continue
        for rank, a in enumerate(rec.get("architectures", [])):
            members = [m for m in a["members"] if m in row_of]
            if not members:
                continue
            signature = "-".join(members)
            aid = arch_id.get(signature)
            if aid is None:
                aid = len(arch_rows)
                arch_id[signature] = aid
                arch_rows.append((aid, signature, len(members), a["n"],
                                  a.get("rep"), a.get("rep_length")))
                member_rows.extend(
                    (aid, pos, row_of[m]) for pos, m in enumerate(members)
                )
            fam_arch_rows.append((home, aid, a["n"], rank))

            # Co-occurrence, counted once per architecture per home family and
            # recorded directionally so Grammarian can say "SH3 before SH2".
            positions = [i for i, m in enumerate(members) if row_of[m] == home]
            if not positions:
                continue
            first = positions[0]
            seen: set[int] = set()
            for pos, m in enumerate(members):
                partner = row_of[m]
                if partner == home or partner in seen:
                    continue
                seen.add(partner)
                slot = cooc[(home, partner)]
                slot[0] += a["n"]
                if pos < first:
                    slot[1] += a["n"]
                else:
                    slot[2] += a["n"]

    db.executemany("INSERT INTO architecture VALUES (?,?,?,?,?,?)", arch_rows)
    db.executemany("INSERT INTO architecture_member VALUES (?,?,?)", member_rows)
    db.executemany("INSERT INTO family_architecture VALUES (?,?,?,?)", fam_arch_rows)

    # Keep only the strongest edges per family: a full graph is mostly noise
    # and the Grammarian only ever draws a couple of dozen nodes.
    by_family: dict[int, list] = defaultdict(list)
    for (home, partner), (n, before, after) in cooc.items():
        by_family[home].append((home, partner, n, before, after))
    cooc_rows = []
    for home, edges in by_family.items():
        edges.sort(key=lambda e: -e[2])
        cooc_rows.extend(edges[:MAX_COOCCURRENCE_PARTNERS])
    db.executemany("INSERT INTO cooccurrence VALUES (?,?,?,?,?)", cooc_rows)

    # ---- meta, indexes, full text ---------------------------------------
    seed_calib = json.loads((build_dir / "whitening.json").read_text())
    calib = json.loads((build_dir / "calibration_real.json").read_text())
    embed = json.loads((build_dir / "stage_embed.json").read_text())
    desc = json.loads((build_dir / "stage_descemb.json").read_text())
    meta = {
        "pfam_release": "38.2",
        "families": str(len(families)),
        "clans": str(len(clan_rows)),
        "architectures": str(len(arch_rows)),
        "protein_model": embed["model"],
        "protein_dim": str(embed["dim"]),
        "text_model": desc["model"],
        "text_dim": str(desc["dim"]),
        "softmax_temperature": str(calib["temperature"]),
        "confidence_high": str(calib["confidence_high"]),
        "confidence_mid": str(calib["confidence_mid"]),
        "abstain_probability": str(calib["abstain_probability"]),
        "real_top1": str(calib["real_top1"]),
        "real_top5": str(calib["real_top5"]),
        "real_top20": str(calib["real_top20"]),
        "real_proteins": str(calib["proteins"]),
        "heldout_seed_top1": str(seed_calib["top1"]),
        "heldout_seed_top5": str(seed_calib["top5"]),
    }
    db.executemany("INSERT INTO meta VALUES (?,?)", list(meta.items()))

    db.executescript(INDEXES)
    db.executescript(FTS)
    db.commit()
    db.execute("VACUUM")
    db.commit()
    db.close()

    return {
        "path": str(out_path),
        "size_mb": round(out_path.stat().st_size / 1e6, 2),
        "families": len(families),
        "clans": len(clan_rows),
        "architectures": len(arch_rows),
        "architecture_members": len(member_rows),
        "family_architecture_links": len(fam_arch_rows),
        "cooccurrence_edges": len(cooc_rows),
        "families_with_ida": len(ida),
        "families_with_counters": len(counters),
    }


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    print(json.dumps(run(root / "assets/build", root / "assets/bundle/pfam.sqlite"), indent=2))
