"""
How much does scanning at several window widths buy?

Pfam domains run from about 30 residues to several hundred. One fixed window
width is a compromise: too narrow and a large domain is never seen whole, too
wide and a small domain is swamped by its neighbours. This measures whether
scanning at several widths and taking the best-scoring window recovers the
families a single width misses. It costs nothing in bundle size, only inference
time, so it is the cheapest lever available.
"""

from __future__ import annotations

import gzip
import json
import sys
from pathlib import Path

import numpy as np
import torch
from transformers import AutoModel, AutoTokenizer

sys.path.insert(0, str(Path(__file__).resolve().parent))
from benchmark_real import MODEL_ID, sample_targets

SCALES = [(96, 32), (160, 48), (256, 64), (384, 96)]


@torch.no_grad()
def main(build_dir: Path, n: int = 400):
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

    def embed(chunks: list[str], width: int) -> np.ndarray:
        enc = tok(chunks, padding=True, truncation=True, max_length=width + 2,
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
        return q / np.clip(np.linalg.norm(q, axis=1, keepdims=True), 1e-9, None)

    def starts(length: int, width: int, stride: int) -> list[int]:
        if length <= width:
            return [0]
        out, offset, last = [], 0, length - width
        while offset < last:
            out.append(offset)
            offset += stride
        out.append(last)
        return out

    # Per-strategy tallies. "cumulative" adds each scale to the ones before it.
    per_scale = {f"{w}": {"top1": 0, "top5": 0} for w, _ in SCALES}
    cumulative = {"top1": 0, "top5": 0, "ranks": []}
    whole = {"top1": 0, "top5": 0}

    for index, (accession, family) in enumerate(usable):
        seq = sequences[accession][:4000]
        truth = row_of[family]
        best_overall = 10**9

        vectors_whole = embed([seq[:1022]], 1022)
        rank_whole = int((vectors_whole[0] @ Cw.T > (vectors_whole[0] @ Cw[truth])).sum())
        whole["top1"] += rank_whole == 0
        whole["top5"] += rank_whole < 5
        best_overall = min(best_overall, rank_whole)

        for width, stride in SCALES:
            chunks = [seq[s : s + width] for s in starts(len(seq), width, stride)]
            q = embed(chunks, width)
            scores = q @ Cw.T
            rank = int((scores > scores[:, truth : truth + 1]).sum(axis=1).min())
            per_scale[f"{width}"]["top1"] += rank == 0
            per_scale[f"{width}"]["top5"] += rank < 5
            best_overall = min(best_overall, rank)

        cumulative["top1"] += best_overall == 0
        cumulative["top5"] += best_overall < 5
        cumulative["ranks"].append(best_overall)

        if index % 50 == 0:
            print(f"\r{index}/{len(usable)}", end="", file=sys.stderr, flush=True)
    print(file=sys.stderr)

    total = len(usable)
    out = {
        "proteins": total,
        "whole_sequence": {k: v / total for k, v in whole.items()},
        "per_scale": {
            k: {m: c / total for m, c in v.items()} for k, v in per_scale.items()
        },
        "all_scales_combined": {
            "top1": cumulative["top1"] / total,
            "top5": cumulative["top5"] / total,
            "median_rank": float(np.median(cumulative["ranks"])),
        },
    }
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main(Path(__file__).resolve().parent.parent / "assets/build")
