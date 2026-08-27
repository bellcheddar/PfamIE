"""
How accurate are the domain boundaries, and does a refinement pass help?

The multi-scale scanner calls a domain wherever a run of windows agrees, so a
boundary is only ever resolved to about one stride: a third of the window
width, and the widest scale strides 96 residues. Human SRC's kinase domain is
really 271-518 and the scanner calls it 385-536.

Ground truth is InterPro's own Pfam locations for real UniProt proteins, so
this measures against the annotation the app is trying to reproduce rather
than against itself.

    .venv/bin/python forge/benchmark_boundaries.py           # current scanner
    .venv/bin/python forge/benchmark_boundaries.py refine    # with refinement
"""

from __future__ import annotations

import gzip
import json
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
import requests
import torch
from transformers import AutoModel, AutoTokenizer

sys.path.insert(0, str(Path(__file__).resolve().parent))
from benchmark_real import MODEL_ID, sample_targets

SCALES = [(96, 32), (160, 48), (256, 64), (384, 96)]
MIN_WINDOW_P, MIN_DOMAIN_P = 0.30, 0.45
MIN_DOMAIN_LEN, OVERLAP_TOLERANCE = 30, 0.35
TEMPERATURE = 0.065

# Refinement pass: narrow tiles, scored against the family that was already
# called, so the boundary is found by where that family's own signal fades.
TILE_WIDTH, TILE_STRIDE = 48, 12
TILE_MARGIN = 0.55       # fraction of the peak a tile must reach to be inside


def device():
    return torch.device("mps") if torch.backends.mps.is_available() else torch.device("cpu")


def fetch_truth(accessions: list[str], cache: Path) -> dict:
    if cache.exists():
        return json.loads(cache.read_text())
    out, lock = {}, threading.Lock()
    session = requests.Session()
    session.headers.update({"User-Agent": "PfamIE-forge/1.0 (marc@marcdeller.com)"})

    def one(acc):
        url = f"https://www.ebi.ac.uk/interpro/api/entry/pfam/protein/uniprot/{acc}/"
        for _ in range(4):
            try:
                r = session.get(url, timeout=60)
                if r.status_code == 204:
                    with lock: out[acc] = []
                    return
                if r.status_code == 200:
                    doms = []
                    for entry in r.json().get("results", []):
                        pf = entry["metadata"]["accession"]
                        for protein in entry.get("proteins", []):
                            for loc in protein.get("entry_protein_locations", []):
                                frags = loc["fragments"]
                                doms.append({
                                    "pfam": pf,
                                    "start": min(f["start"] for f in frags),
                                    "end": max(f["end"] for f in frags),
                                })
                    with lock: out[acc] = doms
                    return
            except requests.RequestException:
                pass
        with lock: out[acc] = []

    with ThreadPoolExecutor(max_workers=12) as pool:
        list(pool.map(one, accessions))
    cache.write_text(json.dumps(out))
    return out


class Scanner:
    def __init__(self, build: Path, index: Path | None = None,
                 model_id: str = MODEL_ID):
        # `build` holds the shared family list; `index` holds the centroids and
        # whitening for whichever model is being tested, so the same benchmark
        # can score t6 and t12 without duplicating anything else.
        self.families = json.loads(
            gzip.open(build / "families.json.gz", "rt", encoding="utf-8").read()
        )
        self.row_of = {f["accession"]: i for i, f in enumerate(self.families)}
        index = index or build
        self.Cw = np.load(index / "centroids_whitened.npy")
        self.mu = np.load(index / "whiten_mu.npy")
        self.W = np.load(index / "whiten_w.npy")
        self.tok = AutoTokenizer.from_pretrained(model_id)
        self.model = AutoModel.from_pretrained(model_id).eval().to(device())

    @torch.no_grad()
    def embed(self, chunks, width):
        enc = self.tok(chunks, padding=True, truncation=True,
                       max_length=width + 2, return_tensors="pt").to(device())
        hidden = self.model(**enc).last_hidden_state
        m = enc["attention_mask"].clone()
        m[:, 0] = 0
        lengths = enc["attention_mask"].sum(1)
        m[torch.arange(m.size(0), device=device()), lengths - 1] = 0
        m = m.unsqueeze(-1).to(hidden.dtype)
        pooled = (hidden * m).sum(1) / m.sum(1).clamp(min=1)
        pooled = torch.nn.functional.normalize(pooled, dim=-1).float().cpu().numpy()
        q = (pooled - self.mu) @ self.W
        return q / np.clip(np.linalg.norm(q, axis=1, keepdims=True), 1e-9, None)

    @staticmethod
    def starts(length, width, stride):
        if length <= width:
            return [0]
        out, off, last = [], 0, length - width
        while off < last:
            out.append(off)
            off += stride
        out.append(last)
        return out

    @staticmethod
    def softmax_top(scores):
        order = np.argsort(-scores)[:20]
        top = scores[order]
        logits = top / TEMPERATURE
        logits -= logits.max()
        p = np.exp(logits)
        p /= p.sum()
        return int(order[0]), float(p[0])

    def segment(self, seq: str) -> list[dict]:
        """
        Per-residue segmentation instead of per-window runs.

        The run-merging scanner assigns a whole window to one family and then
        drops overlapping candidates, so where two domains abut, one wide
        window swallows both and the boundary lands wherever that window
        happened to start. Voting per residue instead lets the boundary fall
        between two strides rather than on a window edge, and lets two adjacent
        domains each win the residues they actually cover.

        Every window still votes for exactly one family, weighted by its
        calibrated probability, so a confident narrow window outvotes a vague
        wide one over the residues they share.
        """
        n = len(seq)
        votes: dict[int, np.ndarray] = {}

        for width, stride in SCALES:
            if width > n and width != SCALES[0][0]:
                continue
            offs = self.starts(n, width, stride)
            q = self.embed([seq[s : s + width] for s in offs], width)
            scores = q @ self.Cw.T
            for i, off in enumerate(offs):
                row, p = self.softmax_top(scores[i])
                if p < MIN_WINDOW_P:
                    continue
                if row not in votes:
                    votes[row] = np.zeros(n, dtype=np.float32)
                # Narrow windows localise better, so weight by probability per
                # residue: a 96-wide window spreads its evidence over fewer
                # residues than a 384-wide one and therefore votes harder.
                votes[row][off : min(off + width, n)] += p * (96.0 / width)

        if not votes:
            return []

        rows = sorted(votes)
        stack = np.stack([votes[r] for r in rows])
        best = stack.argmax(axis=0)
        strength = stack.max(axis=0)
        owner = np.where(strength > 0, best, -1)

        out = []
        i = 0
        while i < n:
            if owner[i] < 0:
                i += 1
                continue
            j = i
            while j + 1 < n and owner[j + 1] == owner[i]:
                j += 1
            if j - i + 1 >= MIN_DOMAIN_LEN:
                row = rows[int(owner[i])]
                out.append({"row": row, "start": i + 1, "end": j + 1,
                            "p": float(strength[i : j + 1].max())})
            i = j + 1
        return out

    def scan(self, seq: str, refine: bool) -> list[dict]:
        n = len(seq)
        candidates = []
        for width, stride in SCALES:
            if width > n and width != SCALES[0][0]:
                continue
            offs = self.starts(n, width, stride)
            q = self.embed([seq[s : s + width] for s in offs], width)
            scores = q @ self.Cw.T
            calls = []
            for i, off in enumerate(offs):
                row, p = self.softmax_top(scores[i])
                calls.append((row if p >= MIN_WINDOW_P else -1, p,
                              off + 1, min(off + width, n)))
            i = 0
            while i < len(calls):
                row = calls[i][0]
                if row < 0:
                    i += 1
                    continue
                j = i
                while j + 1 < len(calls) and calls[j + 1][0] == row:
                    j += 1
                run = calls[i : j + 1]
                best = max(r[1] for r in run)
                if best >= MIN_DOMAIN_P and run[-1][3] - run[0][2] + 1 >= MIN_DOMAIN_LEN:
                    candidates.append({"row": row, "start": run[0][2], "end": run[-1][3],
                                       "p": best})
                i = j + 1

        accepted = []
        for c in sorted(candidates, key=lambda c: -c["p"]):
            clash = False
            for a in accepted:
                ov = min(a["end"], c["end"]) - max(a["start"], c["start"]) + 1
                if ov > 0 and ov / min(a["end"] - a["start"] + 1,
                                       c["end"] - c["start"] + 1) > OVERLAP_TOLERANCE:
                    clash = True
                    break
            if not clash:
                accepted.append(c)
        accepted.sort(key=lambda c: c["start"])

        if refine and accepted and n > TILE_WIDTH * 2:
            accepted = self.refine(seq, accepted)
        return accepted

    def refine(self, seq: str, domains: list[dict]) -> list[dict]:
        """
        One pass of narrow tiles, scored against the family already called.

        The tiles are embedded once and reused for every domain, so the cost is
        a single extra pass regardless of how many domains were found.
        """
        n = len(seq)
        offs = self.starts(n, TILE_WIDTH, TILE_STRIDE)
        q = self.embed([seq[s : s + TILE_WIDTH] for s in offs], TILE_WIDTH)

        out = []
        for d in domains:
            sims = q @ self.Cw[d["row"]]
            peak = float(sims.max())
            if peak <= 0:
                out.append(d)
                continue
            inside = sims >= peak * TILE_MARGIN

            # Take the run of tiles containing the peak, so a homologous patch
            # elsewhere in the protein cannot stretch the call across it.
            centre = int(np.argmax(sims))
            lo = centre
            while lo - 1 >= 0 and inside[lo - 1]:
                lo -= 1
            hi = centre
            while hi + 1 < len(offs) and inside[hi + 1]:
                hi += 1

            start = offs[lo] + 1
            end = min(offs[hi] + TILE_WIDTH, n)
            if end - start + 1 >= MIN_DOMAIN_LEN:
                out.append({**d, "start": start, "end": end})
            else:
                out.append(d)
        return out


def multi_domain_targets(build: Path, n: int, seed: int = 21) -> list[str]:
    """
    Representative proteins of architectures with two or more domains.

    The single-domain sample used elsewhere is the wrong population for a
    boundary benchmark: in a protein that is one domain end to end, almost any
    call scores a high IoU, so the numbers flatter the scanner and say nothing
    about where a boundary actually falls. Boundaries matter precisely where
    domains abut.
    """
    seen: dict[str, int] = {}
    with (build / "ida.jsonl").open() as fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except Exception:
                continue
            for arch in rec.get("architectures", []):
                members = arch.get("members") or []
                if len(members) >= 2 and arch.get("rep") and arch.get("n", 0) >= 5:
                    seen.setdefault(arch["rep"], len(set(members)))
    accessions = sorted(seen)
    rng = np.random.default_rng(seed)
    picks = rng.choice(len(accessions), size=min(n, len(accessions)), replace=False)
    return [accessions[int(i)] for i in picks]


def fetch_sequences_for(accessions: list[str], cache: Path) -> dict:
    if cache.exists():
        return json.loads(cache.read_text())
    from benchmark_real import fetch_sequences
    out = fetch_sequences(accessions)
    cache.write_text(json.dumps(out))
    return out


def main(refine: bool, multi: bool, segment: bool = False, tier: str = "t6"):
    root = Path(__file__).resolve().parent.parent
    build = root / "assets/build"

    if multi:
        picks = multi_domain_targets(build, 220)
        sequences = fetch_sequences_for(picks, build / "multidomain_sequences.json")
        picks = [a for a in picks if sequences.get(a)]
        truth = fetch_truth(picks, build / "boundary_truth_multi.json")
    else:
        sequences = json.loads((build / "calibration_sequences.json").read_text())
        targets = sample_targets(build, 2500, seed=101)
        picks = [a for a, _ in targets if sequences.get(a)][:220]
        truth = fetch_truth(picks, build / "boundary_truth.json")
    if tier == "t12":
        scanner = Scanner(build, root / "assets/build_t12",
                          "facebook/esm2_t12_35M_UR50D")
    else:
        scanner = Scanner(build)

    found = matched = 0
    total_truth = 0
    start_err, end_err, ious = [], [], []

    for i, acc in enumerate(picks):
        real = truth.get(acc) or []
        real = [d for d in real if d["pfam"] in scanner.row_of]
        if not real:
            continue
        total_truth += len(real)
        seq = sequences[acc][:4000]
        called = scanner.segment(seq) if segment else scanner.scan(seq, refine)
        by_row = {}
        for c in called:
            by_row.setdefault(c["row"], []).append(c)

        for d in real:
            row = scanner.row_of[d["pfam"]]
            cands = by_row.get(row)
            if not cands:
                continue
            matched += 1
            # Compare against the called span that overlaps the truth most.
            best = max(cands, key=lambda c: min(c["end"], d["end"]) - max(c["start"], d["start"]))
            start_err.append(abs(best["start"] - d["start"]))
            end_err.append(abs(best["end"] - d["end"]))
            inter = max(0, min(best["end"], d["end"]) - max(best["start"], d["start"]) + 1)
            union = (max(best["end"], d["end"]) - min(best["start"], d["start"]) + 1)
            ious.append(inter / union)
        found += len(called)
        if i % 25 == 0:
            print(f"\r{i}/{len(picks)}", end="", file=sys.stderr, flush=True)
    print(file=sys.stderr)

    print(json.dumps({
        "tier": tier,
        "population": "multi-domain" if multi else "single-domain",
        "mode": "segmented" if segment else ("refined" if refine else "baseline"),
        "proteins": len(picks),
        "true_domains": total_truth,
        "domains_called": found,
        "recall": round(matched / max(total_truth, 1), 4),
        "median_start_error": float(np.median(start_err)) if start_err else None,
        "median_end_error": float(np.median(end_err)) if end_err else None,
        "mean_start_error": round(float(np.mean(start_err)), 1) if start_err else None,
        "mean_end_error": round(float(np.mean(end_err)), 1) if end_err else None,
        "median_iou": round(float(np.median(ious)), 4) if ious else None,
        "iou_over_0.5": round(float(np.mean([i > 0.5 for i in ious])), 4) if ious else None,
    }, indent=2))


if __name__ == "__main__":
    args = set(sys.argv[1:])
    main("refine" in args, "multi" in args, "segment" in args,
         "t12" if "t12" in args else "t6")
