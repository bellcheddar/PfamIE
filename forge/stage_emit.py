"""
PfamIE Data Forge, stage 10: the binary matrices and the manifest.

Three flat, row-major files that the Swift engine memory-maps and hands
straight to vDSP. No headers, no framing: the manifest carries the shapes, and
`family.row` in pfam.sqlite is the row index into all three.
"""

from __future__ import annotations

import hashlib
import json
from datetime import date
from pathlib import Path

import numpy as np


def _write(path: Path, array: np.ndarray) -> dict:
    path.parent.mkdir(parents=True, exist_ok=True)
    array.tofile(path)
    digest = hashlib.sha256(path.read_bytes()).hexdigest()[:16]
    return {
        "file": path.name,
        "shape": list(array.shape),
        "dtype": str(array.dtype),
        "bytes": path.stat().st_size,
        "mb": round(path.stat().st_size / 1e6, 2),
        "sha256_16": digest,
    }


def run(build_dir: Path, out_dir: Path, coreml_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)

    centroids = np.load(build_dir / "centroids_whitened.npy").astype(np.float16)
    coords = np.load(build_dir / "umap3d.npy").astype(np.float32)
    desc = np.load(build_dir / "desc_emb.npy").astype(np.float16)

    files = [
        _write(out_dir / "centroids.bin", np.ascontiguousarray(centroids)),
        _write(out_dir / "umap3d.bin", np.ascontiguousarray(coords)),
        _write(out_dir / "desc_emb.bin", np.ascontiguousarray(desc)),
    ]

    # float16 costs a little precision on a unit vector; confirm it costs
    # nothing that matters before shipping it.
    exact = np.load(build_dir / "centroids_whitened.npy")
    back = centroids.astype(np.float32)
    cos = (exact * back).sum(1) / (
        np.linalg.norm(exact, axis=1) * np.linalg.norm(back, axis=1)
    )

    seed_calib = json.loads((build_dir / "whitening.json").read_text())
    coreml = json.loads((build_dir / "stage_coreml.json").read_text())

    # Confidence comes from the real-protein calibration, never the held-out
    # seed one. Seed sequences are domain-trimmed and drawn from the alignments
    # the centroids were built from; calibrating on them promises an accuracy
    # the app cannot deliver on what users actually paste.
    real_path = build_dir / "calibration_real.json"
    if not real_path.exists():
        raise SystemExit(
            "calibration_real.json is missing. Run forge/stage_calibrate_real.py "
            "before emitting: shipping the seed-fitted confidence would overstate "
            "accuracy by roughly 30 points."
        )
    calib = json.loads(real_path.read_text())

    bundle_files = list(out_dir.rglob("*")) + list(coreml_dir.rglob("*"))
    total = sum(f.stat().st_size for f in bundle_files if f.is_file())

    manifest = {
        "forge_date": date.today().isoformat(),
        "pfam_release": "38.2",
        "families": int(centroids.shape[0]),
        "protein_dim": int(centroids.shape[1]),
        "text_dim": int(desc.shape[1]),
        "files": files,
        "float16_min_cosine": float(cos.min()),
        "float16_mean_cosine": float(cos.mean()),
        "calibration": {
            "temperature": calib["temperature"],
            "confidence_high": calib["confidence_high"],
            "confidence_mid": calib["confidence_mid"],
            "abstain_probability": calib["abstain_probability"],
            # What the app achieves on real UniProt proteins, which is what it
            # is entitled to quote.
            "real_proteins": calib["proteins"],
            "real_top1": calib["real_top1"],
            "real_top5": calib["real_top5"],
            "real_top20": calib["real_top20"],
            "accuracy_high_band": calib["bands"]["high"]["accuracy"],
            "accuracy_mid_band": calib["bands"]["mid"]["accuracy"],
            "accuracy_low_band": calib["bands"]["low"]["accuracy"],
            "accuracy_none_band": calib["bands"]["none"]["accuracy"],
            "fraction_high": calib["bands"]["high"]["fraction"],
            "fraction_mid": calib["bands"]["mid"]["fraction"],
            "fraction_low": calib["bands"]["low"]["fraction"],
            "fraction_none": calib["bands"]["none"]["fraction"],
            # Kept for comparison, and clearly labelled: this is the number
            # that flatters, and it describes the index rather than the app.
            "heldout_seed_top1": seed_calib["top1"],
            "heldout_seed_top5": seed_calib["top5"],
        },
        "models": {
            "protein": {
                "id": coreml["protein_embedder"]["model"],
                "sequence_length": coreml["protein_embedder"]["sequence_length"],
                "parity_cosine_ane": coreml["protein_embedder"]["parity_cosine_ane"],
                "mb": coreml["protein_embedder"]["size_mb"],
            },
            "text": {
                "id": coreml["text_embedder"]["model"],
                "sequence_length": coreml["text_embedder"]["sequence_length"],
                "palettise_bits": coreml["text_embedder"]["palettise_bits"],
                "parity_cosine": coreml["text_embedder"]["parity_cosine"],
                "mb": coreml["text_embedder"]["size_mb"],
            },
        },
        "bundle_total_mb": round(total / 1e6, 2),
    }
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2))
    return manifest


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    print(json.dumps(
        run(root / "assets/build", root / "assets/bundle", root / "assets/coreml"),
        indent=2,
    ))
