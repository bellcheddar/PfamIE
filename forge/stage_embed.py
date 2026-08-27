"""
PfamIE Data Forge, stage 4: ESM-2 embeddings.

Embeds every representative domain sequence with ESM-2 t6-8M, mean-pools over
real residues, and averages each family's sequences into a 320-dimensional
centroid. Held-out sequences are embedded too, and stage 5 uses them to
calibrate the confidence the Oracle reports.

Batches are bucketed by padded width. Varying the sequence-length dimension
freely makes Metal recompile the graph on nearly every batch, which quietly
costs more than the forward passes do.
"""

from __future__ import annotations

import gzip
import json
import time
from pathlib import Path

import numpy as np
import torch
from transformers import AutoModel, AutoTokenizer

import sys as _sys; from pathlib import Path as _Path
_sys.path.insert(0, str(_Path(__file__).resolve().parent))
from model_config import PROTEIN_MODEL_ID as MODEL_ID
WIDTH_BUCKETS = (64, 128, 192, 256, 384, 512, 768, 1024)
TOKENS_PER_BATCH = 32768        # keeps every bucket to a similar amount of work


def _bucket(length: int) -> int:
    for b in WIDTH_BUCKETS:
        if length <= b:
            return b
    return WIDTH_BUCKETS[-1]


def _device() -> torch.device:
    if torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


@torch.no_grad()
def embed_sequences(seqs: list[str], batch_log: str = "") -> np.ndarray:
    """Return an (N, 320) float32 array of L2-normalised mean-pooled embeddings."""
    device = _device()
    tok = AutoTokenizer.from_pretrained(MODEL_ID)
    model = AutoModel.from_pretrained(MODEL_ID).eval().to(device)
    dim = model.config.hidden_size

    out = np.zeros((len(seqs), dim), dtype=np.float32)

    # Group indices by bucket so every batch has one fixed padded width.
    buckets: dict[int, list[int]] = {}
    for i, s in enumerate(seqs):
        buckets.setdefault(_bucket(len(s) + 2), []).append(i)

    started = time.time()
    done = 0
    for width in sorted(buckets):
        idxs = buckets[width]
        per_batch = max(1, TOKENS_PER_BATCH // width)
        for chunk_start in range(0, len(idxs), per_batch):
            chunk = idxs[chunk_start : chunk_start + per_batch]
            batch = [seqs[i] for i in chunk]
            enc = tok(
                batch,
                padding="max_length",
                truncation=True,
                max_length=width,
                return_tensors="pt",
            ).to(device)

            hidden = model(**enc).last_hidden_state          # (B, W, D)

            # Mask out BOS, EOS and padding before pooling.
            mask = enc["attention_mask"].clone()
            mask[:, 0] = 0
            lengths = enc["attention_mask"].sum(dim=1)
            mask[torch.arange(mask.size(0), device=device), lengths - 1] = 0
            mask = mask.unsqueeze(-1).to(hidden.dtype)

            pooled = (hidden * mask).sum(dim=1) / mask.sum(dim=1).clamp(min=1)
            pooled = torch.nn.functional.normalize(pooled, dim=-1)
            out[chunk] = pooled.float().cpu().numpy()

            done += len(chunk)
            if done % 5000 < per_batch:
                rate = done / (time.time() - started)
                print(
                    f"\r{batch_log}embed: {done}/{len(seqs)}  {rate:.0f} seq/s  "
                    f"eta {(len(seqs)-done)/max(rate,1e-6)/60:.1f} min",
                    end="", flush=True,
                )
    print()
    return out


def run(build_dir: Path) -> dict:
    families = json.loads(
        gzip.open(build_dir / "families.json.gz", "rt", encoding="utf-8").read()
    )

    seqs: list[str] = []
    centroid_slices: list[tuple[int, int]] = []
    heldout_rows: list[tuple[int, int]] = []     # (family index, sequence index)

    for fi, fam in enumerate(families):
        start = len(seqs)
        seqs.extend(s["sequence"] for s in fam["centroid_seqs"])
        centroid_slices.append((start, len(seqs)))
    n_centroid_seqs = len(seqs)

    for fi, fam in enumerate(families):
        for s in fam["heldout_seqs"]:
            heldout_rows.append((fi, len(seqs)))
            seqs.append(s["sequence"])

    print(f"embedding {len(seqs)} sequences "
          f"({n_centroid_seqs} centroid, {len(heldout_rows)} held out)")

    emb = embed_sequences(seqs)

    centroids = np.zeros((len(families), emb.shape[1]), dtype=np.float32)
    for fi, (a, b) in enumerate(centroid_slices):
        v = emb[a:b].mean(axis=0)
        n = np.linalg.norm(v)
        centroids[fi] = v / n if n > 0 else v

    heldout_family = np.array([fi for fi, _ in heldout_rows], dtype=np.int32)
    heldout_emb = emb[[ri for _, ri in heldout_rows]] if heldout_rows else np.zeros((0, emb.shape[1]), np.float32)

    np.save(build_dir / "centroids.npy", centroids)
    np.save(build_dir / "heldout_emb.npy", heldout_emb)
    np.save(build_dir / "heldout_family.npy", heldout_family)

    stats = {
        "model": MODEL_ID,
        "dim": int(emb.shape[1]),
        "families": len(families),
        "sequences_embedded": len(seqs),
        "heldout": int(heldout_emb.shape[0]),
        "device": str(_device()),
    }
    (build_dir / "stage_embed.json").write_text(json.dumps(stats, indent=2))
    return stats


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    print(json.dumps(run(root / "assets/build"), indent=2))
