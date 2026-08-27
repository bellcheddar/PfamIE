"""
An external benchmark: real UniProt proteins, not Pfam seed sequences.

Held-out seed sequences measure whether a centroid recognises another member of
its own seed alignment, and how flattering that is depends entirely on how the
seed members were chosen. Two selection strategies cannot be compared on it,
because each writes its own exam.

This uses the representative proteins InterPro named for single-domain
architectures: real sequences, a known family, and nothing to do with how the
centroid's members were picked.
"""

from __future__ import annotations

import gzip
import json
import sys
import time
from pathlib import Path

import numpy as np
import requests
import torch
from transformers import AutoModel, AutoTokenizer

import sys as _sys; from pathlib import Path as _Path
_sys.path.insert(0, str(_Path(__file__).resolve().parent))
from model_config import PROTEIN_MODEL_ID as MODEL_ID
UNIPROT_STREAM = "https://rest.uniprot.org/uniprotkb/stream"


def sample_targets(build_dir: Path, n: int, seed: int = 7) -> list[tuple[str, str]]:
    """(uniprot accession, expected Pfam accession) for single-domain proteins."""
    families = json.loads(
        gzip.open(build_dir / "families.json.gz", "rt", encoding="utf-8").read()
    )
    known = {f["accession"] for f in families}

    targets: list[tuple[str, str]] = []
    with (build_dir / "ida.jsonl").open() as fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except Exception:
                continue
            if rec["accession"] not in known:
                continue
            for arch in rec.get("architectures", []):
                # Single-domain only: a multi-domain protein has no single
                # correct whole-sequence answer, so it would measure something
                # else. The domain scanner is tested separately.
                if len(arch["members"]) == 1 and arch.get("rep") and arch["n"] >= 5:
                    targets.append((arch["rep"], rec["accession"]))
                    break

    rng = np.random.default_rng(seed)
    picks = rng.choice(len(targets), size=min(n, len(targets)), replace=False)
    return [targets[int(i)] for i in picks]


def fetch_sequences(accessions: list[str], chunk: int = 100) -> dict[str, str]:
    out: dict[str, str] = {}
    session = requests.Session()
    for start in range(0, len(accessions), chunk):
        batch = accessions[start : start + chunk]
        query = " OR ".join(f"accession:{a}" for a in batch)
        for attempt in range(4):
            try:
                r = session.get(
                    UNIPROT_STREAM,
                    params={"query": query, "format": "fasta"},
                    timeout=120,
                )
                if r.status_code == 200:
                    break
            except requests.RequestException:
                pass
            time.sleep(3 * (attempt + 1))
        else:
            continue

        accession = None
        parts: list[str] = []
        for line in r.text.splitlines():
            if line.startswith(">"):
                if accession:
                    out[accession] = "".join(parts)
                accession = line.split("|")[1] if "|" in line else None
                parts = []
            elif accession:
                parts.append(line.strip())
        if accession:
            out[accession] = "".join(parts)
        print(f"\rfetched {len(out)}/{len(accessions)}", end="", file=sys.stderr, flush=True)
    print(file=sys.stderr)
    return out


@torch.no_grad()
def run(build_dir: Path, n: int = 400) -> dict:
    families = json.loads(
        gzip.open(build_dir / "families.json.gz", "rt", encoding="utf-8").read()
    )
    row_of = {f["accession"]: i for i, f in enumerate(families)}
    Cw = np.load(build_dir / "centroids_whitened.npy")
    mu = np.load(build_dir / "whiten_mu.npy")
    W = np.load(build_dir / "whiten_w.npy")

    cache = build_dir / "benchmark_sequences.json"
    targets = sample_targets(build_dir, n)
    if cache.exists():
        sequences = json.loads(cache.read_text())
    else:
        sequences = fetch_sequences([a for a, _ in targets])
        cache.write_text(json.dumps(sequences))

    device = torch.device("mps") if torch.backends.mps.is_available() else torch.device("cpu")
    tok = AutoTokenizer.from_pretrained(MODEL_ID)
    model = AutoModel.from_pretrained(MODEL_ID).eval().to(device)

    usable = [(a, f) for a, f in targets if sequences.get(a) and f in row_of]
    hits1 = hits5 = hits20 = 0
    ranks: list[int] = []

    for start in range(0, len(usable), 32):
        batch = usable[start : start + 32]
        seqs = [sequences[a][:1022] for a, _ in batch]
        enc = tok(seqs, padding=True, truncation=True, max_length=1024,
                  return_tensors="pt").to(device)
        hidden = model(**enc).last_hidden_state
        mask = enc["attention_mask"].clone()
        mask[:, 0] = 0
        lengths = enc["attention_mask"].sum(1)
        mask[torch.arange(mask.size(0), device=device), lengths - 1] = 0
        mask = mask.unsqueeze(-1).to(hidden.dtype)
        pooled = (hidden * mask).sum(1) / mask.sum(1).clamp(min=1)
        pooled = torch.nn.functional.normalize(pooled, dim=-1).float().cpu().numpy()

        q = (pooled - mu) @ W
        q /= np.clip(np.linalg.norm(q, axis=1, keepdims=True), 1e-9, None)
        scores = q @ Cw.T
        for (_, family), row_scores in zip(batch, scores):
            truth = row_of[family]
            order = np.argsort(-row_scores)
            rank = int(np.where(order == truth)[0][0])
            ranks.append(rank)
            hits1 += rank == 0
            hits5 += rank < 5
            hits20 += rank < 20

    total = max(len(usable), 1)
    return {
        "proteins": len(usable),
        "top1": hits1 / total,
        "top5": hits5 / total,
        "top20": hits20 / total,
        "median_rank": float(np.median(ranks)) if ranks else None,
    }


@torch.no_grad()
def run_windowed(build_dir: Path, n: int = 400, window: int = 160, stride: int = 40) -> dict:
    """
    The same 400 real proteins, but scanned the way the app scans them.

    A real protein is not a trimmed domain: it carries signal peptides,
    linkers, low-complexity tails and often other domains, and a single
    whole-sequence embedding averages all of that into the answer. The sliding
    window is the app's actual primary path, so it is the one worth measuring.
    """
    families = json.loads(
        gzip.open(build_dir / "families.json.gz", "rt", encoding="utf-8").read()
    )
    row_of = {f["accession"]: i for i, f in enumerate(families)}
    Cw = np.load(build_dir / "centroids_whitened.npy")
    mu = np.load(build_dir / "whiten_mu.npy")
    W = np.load(build_dir / "whiten_w.npy")

    sequences = json.loads((build_dir / "benchmark_sequences.json").read_text())
    targets = sample_targets(build_dir, n)
    usable = [(a, f) for a, f in targets if sequences.get(a) and f in row_of]

    device = torch.device("mps") if torch.backends.mps.is_available() else torch.device("cpu")
    tok = AutoTokenizer.from_pretrained(MODEL_ID)
    model = AutoModel.from_pretrained(MODEL_ID).eval().to(device)

    def starts(length: int) -> list[int]:
        if length <= window:
            return [0]
        out, offset, last = [], 0, length - window
        while offset < last:
            out.append(offset)
            offset += stride
        out.append(last)
        return out

    best1 = best5 = 0
    ranks = []
    for index, (accession, family) in enumerate(usable):
        seq = sequences[accession][:4000]
        chunks = [seq[s : s + window] for s in starts(len(seq))]
        enc = tok(chunks, padding=True, truncation=True, max_length=window + 2,
                  return_tensors="pt").to(device)
        hidden = model(**enc).last_hidden_state
        mask = enc["attention_mask"].clone()
        mask[:, 0] = 0
        lengths = enc["attention_mask"].sum(1)
        mask[torch.arange(mask.size(0), device=device), lengths - 1] = 0
        mask = mask.unsqueeze(-1).to(hidden.dtype)
        pooled = (hidden * mask).sum(1) / mask.sum(1).clamp(min=1)
        pooled = torch.nn.functional.normalize(pooled, dim=-1).float().cpu().numpy()

        q = (pooled - mu) @ W
        q /= np.clip(np.linalg.norm(q, axis=1, keepdims=True), 1e-9, None)
        scores = q @ Cw.T                       # (windows, families)

        truth = row_of[family]
        # Best rank the true family achieves in any single window: that is what
        # the scanner needs, since one confident window is enough to call it.
        per_window_rank = (scores > scores[:, truth : truth + 1]).sum(axis=1)
        rank = int(per_window_rank.min())
        ranks.append(rank)
        best1 += rank == 0
        best5 += rank < 5
        if index % 50 == 0:
            print(f"\rwindowed {index}/{len(usable)}", end="", file=sys.stderr, flush=True)
    print(file=sys.stderr)

    total = max(len(usable), 1)
    return {
        "proteins": len(usable),
        "window": window,
        "stride": stride,
        "best_window_top1": best1 / total,
        "best_window_top5": best5 / total,
        "median_best_rank": float(np.median(ranks)),
    }


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    mode = sys.argv[1] if len(sys.argv) > 1 else "whole"
    fn = run_windowed if mode == "windowed" else run
    print(json.dumps(fn(root / "assets/build"), indent=2))
