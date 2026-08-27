"""
PfamIE Data Forge, stage 5b: calibrate confidence on real proteins.

Stage 5 fits the softmax temperature against held-out Pfam seed sequences. That
measures the index against its own kind: seed sequences are trimmed to domain
boundaries and drawn from the alignments the centroids were built from, and the
resulting confidence is badly over-optimistic for what the app is actually
handed. Measured on the same pipeline, top-1 is 0.72 on held-out seeds and 0.53
on real UniProt proteins, so a probability calibrated on the former promises
something the latter cannot deliver: an all-alanine nonsense sequence scored
0.51 and a wrong call scored 0.79.

This stage re-fits temperature and the band thresholds against real proteins
scanned exactly the way the app scans them: multi-scale windows, softmax over
one window's top-20 shortlist, headline taken from the best-reading window.

The set is split, so the reported accuracies are measured on proteins the
thresholds were not chosen on.
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
from benchmark_real import MODEL_ID, fetch_sequences, sample_targets

SCALES = [(96, 32), (160, 48), (256, 64), (384, 96)]
SHORTLIST = 20              # must match CentroidIndex's k
CALIBRATION_FRACTION = 0.75


@torch.no_grad()
def collect(build_dir: Path, n: int) -> tuple[np.ndarray, np.ndarray]:
    """
    Returns (shortlist_similarities, correct_index) per protein.

    `shortlist_similarities` is the best-reading window's top-20 cosines, which
    is exactly the vector the app softmaxes. `correct_index` is where the true
    family sits in that shortlist, or -1 when it missed it entirely: those rows
    still matter, because the model should be unconfident on them.
    """
    families = json.loads(
        gzip.open(build_dir / "families.json.gz", "rt", encoding="utf-8").read()
    )
    row_of = {f["accession"]: i for i, f in enumerate(families)}
    Cw = np.load(build_dir / "centroids_whitened.npy")
    mu = np.load(build_dir / "whiten_mu.npy")
    W = np.load(build_dir / "whiten_w.npy")

    targets = sample_targets(build_dir, n, seed=101)
    cache = build_dir / "calibration_sequences.json"
    if cache.exists():
        sequences = json.loads(cache.read_text())
    else:
        sequences = fetch_sequences([a for a, _ in targets])
        cache.write_text(json.dumps(sequences))

    usable = [(a, f) for a, f in targets if sequences.get(a) and f in row_of]
    print(f"calibrating on {len(usable)} real proteins", file=sys.stderr)

    device = torch.device("mps") if torch.backends.mps.is_available() else torch.device("cpu")
    tok = AutoTokenizer.from_pretrained(MODEL_ID)
    model = AutoModel.from_pretrained(MODEL_ID).eval().to(device)

    def embed(chunks, width):
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

    def starts(length, width, stride):
        if length <= width:
            return [0]
        out, offset, last = [], 0, length - width
        while offset < last:
            out.append(offset)
            offset += stride
        out.append(last)
        return out

    shortlists, correct = [], []
    for index, (accession, family) in enumerate(usable):
        seq = sequences[accession][:4000]
        truth = row_of[family]

        best_row = None
        best_peak = -np.inf
        for width, stride in SCALES:
            if width > len(seq) and width != SCALES[0][0]:
                continue
            chunks = [seq[s : s + width] for s in starts(len(seq), width, stride)]
            q = embed(chunks, width)
            scores = q @ Cw.T
            peaks = scores.max(axis=1)
            pick = int(np.argmax(peaks))
            if peaks[pick] > best_peak:
                best_peak = float(peaks[pick])
                best_row = scores[pick]

        # The whole sequence competes with the windows, as it does in the app.
        q = embed([seq[:1022]], 1022)
        whole = (q @ Cw.T)[0]
        if whole.max() > best_peak:
            best_row = whole

        order = np.argsort(-best_row)[:SHORTLIST]
        shortlists.append(best_row[order])
        hit = np.where(order == truth)[0]
        correct.append(int(hit[0]) if len(hit) else -1)

        if index % 100 == 0:
            print(f"\r{index}/{len(usable)}", end="", file=sys.stderr, flush=True)
    print(file=sys.stderr)
    return np.array(shortlists), np.array(correct)


def fit(S: np.ndarray, correct: np.ndarray) -> dict:
    split = int(len(S) * CALIBRATION_FRACTION)
    fit_S, fit_c = S[:split], correct[:split]
    test_S, test_c = S[split:], correct[split:]

    def probabilities(shortlists, temperature):
        logits = shortlists / temperature
        logits -= logits.max(axis=1, keepdims=True)
        p = np.exp(logits)
        return p / p.sum(axis=1, keepdims=True)

    best_t, best_nll = 1.0, np.inf
    for t in np.concatenate([np.arange(0.01, 0.3, 0.005), np.arange(0.3, 3.0, 0.02)]):
        p = probabilities(fit_S, t)
        hit = fit_c >= 0
        nll = -np.log(np.clip(p[hit, fit_c[hit]], 1e-12, None)).sum()
        nll += -np.log(np.clip(1.0 - p[~hit, 0], 1e-12, None)).sum()
        nll /= len(fit_c)
        if nll < best_nll:
            best_nll, best_t = nll, float(t)

    p_fit = probabilities(fit_S, best_t)[:, 0]
    right_fit = fit_c == 0
    grid = np.round(np.arange(0.05, 1.0, 0.05), 2)

    def band_accuracy(p, right, lo, hi):
        sel = (p >= lo) & (p < hi)
        return (float(right[sel].mean()) if sel.sum() else 0.0), int(sel.sum())

    def lowest_cut(target):
        for cut in grid:
            bins = [band_accuracy(p_fit, right_fit, lo, lo + 0.05)
                    for lo in grid if lo >= cut]
            usable = [a for a, n in bins if n >= 25]
            if usable and min(usable) >= target:
                return float(cut)
        return 1.0

    high = lowest_cut(0.80)
    mid = lowest_cut(0.45)
    abstain = 0.05
    for cut in grid:
        acc, n = band_accuracy(p_fit, right_fit, cut, cut + 0.05)
        if n >= 25 and acc >= 0.20:
            abstain = float(cut)
            break

    # Everything reported is measured on the held-back split.
    p_test = probabilities(test_S, best_t)[:, 0]
    right_test = test_c == 0

    def report(lo, hi):
        sel = (p_test >= lo) & (p_test < hi)
        return {
            "fraction": float(sel.mean()),
            "accuracy": float(right_test[sel].mean()) if sel.sum() else 0.0,
            "n": int(sel.sum()),
        }

    return {
        "proteins": int(len(S)),
        "fitted_on": int(split),
        "tested_on": int(len(S) - split),
        "temperature": best_t,
        "nll": float(best_nll),
        "confidence_high": high,
        "confidence_mid": mid,
        "abstain_probability": abstain,
        "real_top1": float((correct == 0).mean()),
        "real_top5": float(((correct >= 0) & (correct < 5)).mean()),
        "real_top20": float((correct >= 0).mean()),
        "bands": {
            "high": report(high, 1.01),
            "mid": report(mid, high),
            "low": report(abstain, mid),
            "none": report(0.0, abstain),
        },
        "reliability": [
            {
                "lo": round(float(lo), 2),
                "hi": round(float(lo + 0.05), 2),
                "n": band_accuracy(p_test, right_test, lo, lo + 0.05)[1],
                "accuracy": round(band_accuracy(p_test, right_test, lo, lo + 0.05)[0], 4),
            }
            for lo in grid
        ],
    }


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    build = root / "assets/build"
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 2500
    S, correct = collect(build, n)
    result = fit(S, correct)
    (build / "calibration_real.json").write_text(json.dumps(result, indent=2))
    printable = {k: v for k, v in result.items() if k != "reliability"}
    print(json.dumps(printable, indent=2))
