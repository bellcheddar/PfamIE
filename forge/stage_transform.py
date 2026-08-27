"""
PfamIE Data Forge, stage 5: whitening transform and confidence calibration.

Mean-pooled protein language model embeddings are strongly anisotropic: a
single common direction dominates, every pair of families sits at cosine ~0.97,
and short families collapse into one hub. Measured on 26,286 held-out seed
sequences, whitening the centroid covariance lifts top-1 family recovery from
0.514 to ~0.60 and pulls the mean nearest-neighbour cosine from 0.968 to 0.677,
which is what makes the Galaxy's geometry mean anything at all.

The transform is 320x320 plus a 320 mean vector, so it ships with the app and
the Swift engine applies it to every query embedding:

    v = normalise((embed(seq) - mu) @ W)

This stage also fits the softmax temperature the Oracle uses to turn cosine
similarities into a confidence, and records the thresholds that separate the
High / Mid / Low bands honestly.
"""

from __future__ import annotations

import gzip
import json
from pathlib import Path

import numpy as np

ALPHA = 1.0          # full whitening; the sweep in assets/build/whiten_sweep2.log plateaus here
EPS = 1e-5
TOPK_FOR_SOFTMAX = 20    # the Oracle only ever softmaxes over the shortlist it shows


def normalise(X: np.ndarray) -> np.ndarray:
    return X / np.clip(np.linalg.norm(X, axis=1, keepdims=True), 1e-9, None)


def fit_whitening(C: np.ndarray, alpha: float, eps: float):
    mu = C.mean(axis=0, keepdims=True).astype(np.float32)
    X = C - mu
    cov = (X.T @ X) / len(X)
    w, V = np.linalg.eigh(cov)
    W = (V @ np.diag(np.clip(w, eps, None) ** (-alpha / 2.0)) @ V.T).astype(np.float32)
    return mu, W


def fit_temperature(S_top: np.ndarray, correct: np.ndarray) -> float:
    """
    Fit the softmax temperature that minimises negative log likelihood over the
    top-k shortlist. `S_top` is (N, k) cosine similarities, `correct` is the
    column index of the true family, or -1 when the true family missed the
    shortlist (those rows still contribute: the model should be unconfident).
    """
    best_t, best_nll = 1.0, float("inf")
    for t in np.concatenate([np.arange(0.01, 0.2, 0.005), np.arange(0.2, 2.01, 0.02)]):
        logits = S_top / t
        logits -= logits.max(axis=1, keepdims=True)
        p = np.exp(logits)
        p /= p.sum(axis=1, keepdims=True)
        hit = correct >= 0
        # Rows whose true family missed the shortlist are scored on how little
        # probability mass the (wrong) top hit was given.
        nll = -np.log(np.clip(p[hit, correct[hit]], 1e-12, None)).sum()
        nll += -np.log(np.clip(1.0 - p[~hit, 0], 1e-12, None)).sum()
        nll /= len(correct)
        if nll < best_nll:
            best_nll, best_t = nll, float(t)
    return best_t, best_nll


def run(build_dir: Path, alpha: float = ALPHA, eps: float = EPS) -> dict:
    C = np.load(build_dir / "centroids.npy")
    H = np.load(build_dir / "heldout_emb.npy")
    HF = np.load(build_dir / "heldout_family.npy")

    mu, W = fit_whitening(C, alpha, eps)
    Cw = normalise((C - mu) @ W)
    Hw = normalise((H - mu) @ W)

    S = Hw @ Cw.T
    order = np.argpartition(-S, TOPK_FOR_SOFTMAX, axis=1)[:, :TOPK_FOR_SOFTMAX]
    rows = np.arange(len(S))[:, None]
    S_top = S[rows, order]
    resort = np.argsort(-S_top, axis=1)
    S_top = S_top[rows, resort]
    order = order[rows, resort]

    correct = np.full(len(S), -1, dtype=np.int64)
    match = order == HF[:, None]
    has = match.any(axis=1)
    correct[has] = match.argmax(axis=1)[has]

    top1 = float((order[:, 0] == HF).mean())
    top5 = float((correct >= 0) [correct < 5].size and ((correct >= 0) & (correct < 5)).mean())
    top20 = float((correct >= 0).mean())

    temperature, nll = fit_temperature(S_top.astype(np.float64), correct)

    # Honest confidence bands, read off the reliability curve rather than
    # guessed. The earlier version compared *cumulative* accuracy above a cut,
    # which happily labelled a bucket "Mid" that was right 18% of the time.
    # What a band must promise is the accuracy of queries landing *inside* it.
    logits = S_top / temperature
    logits -= logits.max(axis=1, keepdims=True)
    P = np.exp(logits)
    P /= P.sum(axis=1, keepdims=True)
    p1 = P[:, 0]
    right = order[:, 0] == HF

    grid = np.round(np.arange(0.05, 1.00, 0.05), 2)

    def band_accuracy(lo: float, hi: float) -> tuple[float, int]:
        sel = (p1 >= lo) & (p1 < hi)
        n = int(sel.sum())
        return (float(right[sel].mean()) if n else 0.0), n

    def lowest_cut_with(target: float) -> float:
        """Smallest p1 at which every 0.05-wide bin above it is >= target."""
        for cut in grid:
            bins = [band_accuracy(lo, lo + 0.05) for lo in grid if lo >= cut]
            usable = [a for a, n in bins if n >= 100]
            if usable and min(usable) >= target:
                return float(cut)
        return 1.0

    high_cut = lowest_cut_with(0.85)
    mid_cut = lowest_cut_with(0.45)
    # Below this the top hit is right barely one time in five: the Oracle says
    # "no confident family" rather than naming one.
    abstain_cut = 0.05
    for cut in grid:
        acc, n = band_accuracy(cut, cut + 0.05)
        if n >= 100 and acc >= 0.20:
            abstain_cut = float(cut)
            break

    # Cosine alone separates right from wrong far less cleanly than the
    # calibrated probability does (right median 0.72 vs wrong 0.50, with real
    # overlap), so it is recorded for the UI but never used as the gate.
    abstain_cos = float(np.quantile(S_top[~right, 0], 0.9)) if (~right).any() else 0.0

    reliability = [
        {"lo": round(float(lo), 2), "hi": round(float(lo + 0.05), 2),
         "n": band_accuracy(lo, lo + 0.05)[1],
         "accuracy": round(band_accuracy(lo, lo + 0.05)[0], 4)}
        for lo in grid
    ]

    np.save(build_dir / "whiten_mu.npy", mu.astype(np.float32))
    np.save(build_dir / "whiten_w.npy", W.astype(np.float32))
    np.save(build_dir / "centroids_whitened.npy", Cw.astype(np.float32))

    stats = {
        "alpha": alpha,
        "eps": eps,
        "heldout": int(len(S)),
        "top1": top1,
        "top5": top5,
        "top20": top20,
        "temperature": temperature,
        "nll": nll,
        "confidence_high": high_cut,
        "confidence_mid": mid_cut,
        "abstain_probability": abstain_cut,
        "abstain_cosine": abstain_cos,
        "accuracy_high_band": float(right[p1 >= high_cut].mean()) if (p1 >= high_cut).any() else 0.0,
        "accuracy_mid_band": float(right[(p1 >= mid_cut) & (p1 < high_cut)].mean())
        if ((p1 >= mid_cut) & (p1 < high_cut)).any() else 0.0,
        "accuracy_low_band": float(right[(p1 >= abstain_cut) & (p1 < mid_cut)].mean())
        if ((p1 >= abstain_cut) & (p1 < mid_cut)).any() else 0.0,
        "accuracy_abstain_band": float(right[p1 < abstain_cut].mean()) if (p1 < abstain_cut).any() else 0.0,
        "fraction_high": float((p1 >= high_cut).mean()),
        "fraction_mid": float(((p1 >= mid_cut) & (p1 < high_cut)).mean()),
        "fraction_low": float(((p1 >= abstain_cut) & (p1 < mid_cut)).mean()),
        "fraction_abstain": float((p1 < abstain_cut).mean()),
        "reliability": reliability,
    }
    (build_dir / "whitening.json").write_text(json.dumps(stats, indent=2))
    return stats


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--alpha", type=float, default=ALPHA)
    ap.add_argument("--eps", type=float, default=EPS)
    args = ap.parse_args()
    root = Path(__file__).resolve().parent.parent
    print(json.dumps(run(root / "assets/build", args.alpha, args.eps), indent=2))
