"""
Is a bigger protein language model worth it?

ESM-2 t6-8M is 8 million parameters, and the honest ceiling of the current
build is 0.43 top-1 on real proteins. The obvious lever is the next tier up,
t12-35M, which is 4.4x the parameters and 480 dimensions instead of 320.

This builds a complete alternative index in its own namespace and scores it on
exactly the same benchmarks as the shipped one, so the comparison is like for
like: the same families, the same stratified seed sequences, the same whitening
recipe, the same real UniProt proteins, and the same multi-scale scan. The
existing assets are never touched, so a negative result costs nothing.

    .venv/bin/python forge/eval_model_tier.py facebook/esm2_t12_35M_UR50D t12
"""

from __future__ import annotations

import gzip
import json
import sys
import time
from pathlib import Path

import numpy as np
import torch
from transformers import AutoModel, AutoTokenizer

WIDTH_BUCKETS = (64, 128, 192, 256, 384, 512, 768, 1024)
TOKENS_PER_BATCH = 24576
SCALES = [(96, 32), (160, 48), (256, 64), (384, 96)]
ALPHA, EPS = 1.0, 1e-5


def device() -> torch.device:
    return torch.device("mps") if torch.backends.mps.is_available() else torch.device("cpu")


def bucket(length: int) -> int:
    for b in WIDTH_BUCKETS:
        if length <= b:
            return b
    return WIDTH_BUCKETS[-1]


@torch.no_grad()
def embed_all(model, tok, seqs: list[str], label: str) -> np.ndarray:
    dim = model.config.hidden_size
    out = np.zeros((len(seqs), dim), dtype=np.float32)
    buckets: dict[int, list[int]] = {}
    for i, s in enumerate(seqs):
        buckets.setdefault(bucket(len(s) + 2), []).append(i)

    started, done = time.time(), 0
    for width in sorted(buckets):
        idxs = buckets[width]
        per_batch = max(1, TOKENS_PER_BATCH // width)
        for start in range(0, len(idxs), per_batch):
            chunk = idxs[start : start + per_batch]
            enc = tok([seqs[i] for i in chunk], padding="max_length", truncation=True,
                      max_length=width, return_tensors="pt").to(device())
            hidden = model(**enc).last_hidden_state
            mask = enc["attention_mask"].clone()
            mask[:, 0] = 0
            lengths = enc["attention_mask"].sum(1)
            mask[torch.arange(mask.size(0), device=device()), lengths - 1] = 0
            mask = mask.unsqueeze(-1).to(hidden.dtype)
            pooled = (hidden * mask).sum(1) / mask.sum(1).clamp(min=1)
            pooled = torch.nn.functional.normalize(pooled, dim=-1)
            out[chunk] = pooled.float().cpu().numpy()
            done += len(chunk)
            if done % 10000 < per_batch:
                rate = done / (time.time() - started)
                print(f"\r{label}: {done}/{len(seqs)}  {rate:.0f}/s  "
                      f"eta {(len(seqs)-done)/max(rate,1e-6)/60:.1f} min",
                      end="", file=sys.stderr, flush=True)
    print(file=sys.stderr)
    return out


def normalise(X):
    return X / np.clip(np.linalg.norm(X, axis=1, keepdims=True), 1e-9, None)


def main(model_id: str, tag: str):
    root = Path(__file__).resolve().parent.parent
    shared = root / "assets/build"
    out_dir = root / f"assets/build_{tag}"
    out_dir.mkdir(parents=True, exist_ok=True)

    families = json.loads(
        gzip.open(shared / "families.json.gz", "rt", encoding="utf-8").read()
    )
    row_of = {f["accession"]: i for i, f in enumerate(families)}

    tok = AutoTokenizer.from_pretrained(model_id)
    model = AutoModel.from_pretrained(model_id).eval().to(device())
    dim = model.config.hidden_size
    params = sum(p.numel() for p in model.parameters())
    print(f"{model_id}: {params/1e6:.1f}M parameters, {dim} dimensions", file=sys.stderr)

    centroids_path = out_dir / "centroids.npy"
    if centroids_path.exists():
        C = np.load(centroids_path)
        H = np.load(out_dir / "heldout_emb.npy")
        HF = np.load(out_dir / "heldout_family.npy")
    else:
        seqs, slices, held_rows = [], [], []
        for f in families:
            start = len(seqs)
            seqs.extend(s["sequence"] for s in f["centroid_seqs"])
            slices.append((start, len(seqs)))
        for fi, f in enumerate(families):
            for s in f["heldout_seqs"]:
                held_rows.append((fi, len(seqs)))
                seqs.append(s["sequence"])

        emb = embed_all(model, tok, seqs, f"{tag} centroids")
        C = np.zeros((len(families), dim), dtype=np.float32)
        for fi, (a, b) in enumerate(slices):
            v = emb[a:b].mean(axis=0)
            n = np.linalg.norm(v)
            C[fi] = v / n if n > 0 else v
        HF = np.array([fi for fi, _ in held_rows], dtype=np.int32)
        H = emb[[r for _, r in held_rows]]
        np.save(centroids_path, C)
        np.save(out_dir / "heldout_emb.npy", H)
        np.save(out_dir / "heldout_family.npy", HF)

    mu = C.mean(axis=0, keepdims=True)
    X = C - mu
    cov = (X.T @ X) / len(X)
    w, V = np.linalg.eigh(cov)
    W = (V @ np.diag(np.clip(w, EPS, None) ** (-ALPHA / 2.0)) @ V.T).astype(np.float32)
    Cw = normalise(X @ W)
    np.save(out_dir / "whiten_mu.npy", mu.astype(np.float32))
    np.save(out_dir / "whiten_w.npy", W)
    np.save(out_dir / "centroids_whitened.npy", Cw)

    # Seed benchmark, for comparison with the number in the repo history.
    Hw = normalise((H - mu) @ W)
    order = np.argsort(-(Hw @ Cw.T), axis=1)[:, :20]
    seed = {
        "top1": float((order[:, 0] == HF).mean()),
        "top5": float((order[:, :5] == HF[:, None]).any(1).mean()),
        "heldout": int(len(HF)),
    }
    print(f"seed benchmark: {json.dumps(seed)}", file=sys.stderr)

    # Real-protein benchmark, the one that decides.
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from benchmark_real import sample_targets

    sequences = json.loads((shared / "calibration_sequences.json").read_text())
    targets = sample_targets(shared, 2500, seed=101)
    usable = [(a, f) for a, f in targets if sequences.get(a) and f in row_of]

    def starts(length, width, stride):
        if length <= width:
            return [0]
        out, off, last = [], 0, length - width
        while off < last:
            out.append(off)
            off += stride
        out.append(last)
        return out

    hits1 = hits5 = 0
    for i, (accession, family) in enumerate(usable):
        seq = sequences[accession][:4000]
        truth = row_of[family]
        best_peak, best_row = -np.inf, None
        for width, stride in SCALES:
            if width > len(seq) and width != SCALES[0][0]:
                continue
            chunks = [seq[s : s + width] for s in starts(len(seq), width, stride)]
            q = embed_all(model, tok, chunks, "") if False else None
            enc = tok(chunks, padding=True, truncation=True, max_length=width + 2,
                      return_tensors="pt").to(device())
            with torch.no_grad():
                hidden = model(**enc).last_hidden_state
            m = enc["attention_mask"].clone()
            m[:, 0] = 0
            lengths = enc["attention_mask"].sum(1)
            m[torch.arange(m.size(0), device=device()), lengths - 1] = 0
            m = m.unsqueeze(-1).to(hidden.dtype)
            pooled = (hidden * m).sum(1) / m.sum(1).clamp(min=1)
            pooled = torch.nn.functional.normalize(pooled, dim=-1).float().cpu().numpy()
            qq = normalise((pooled - mu) @ W)
            scores = qq @ Cw.T
            peaks = scores.max(axis=1)
            pick = int(np.argmax(peaks))
            if peaks[pick] > best_peak:
                best_peak, best_row = float(peaks[pick]), scores[pick]
        order = np.argsort(-best_row)[:20]
        hits1 += int(order[0] == truth)
        hits5 += int(truth in order[:5])
        if i % 100 == 0:
            print(f"\r{tag} real: {i}/{len(usable)}", end="", file=sys.stderr, flush=True)
    print(file=sys.stderr)

    result = {
        "model": model_id,
        "parameters_millions": round(params / 1e6, 1),
        "dimensions": dim,
        "seed_benchmark": seed,
        "real_proteins": len(usable),
        "real_top1": hits1 / max(len(usable), 1),
        "real_top5": hits5 / max(len(usable), 1),
        "centroids_mb_float16": round(len(families) * dim * 2 / 1e6, 1),
    }
    (out_dir / "evaluation.json").write_text(json.dumps(result, indent=2))
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
