"""
PfamIE Data Forge, stage 7: the Galaxy's 3D coordinates.

3D UMAP over the whitened centroids. Whitened, not raw: in raw space every
family sits at cosine ~0.97 to every other and UMAP renders a featureless ball.
"""

from __future__ import annotations

import gzip
import json
from pathlib import Path

import numpy as np

N_NEIGHBORS = 25
MIN_DIST = 0.08
SEED = 20260827          # fixed, so the Galaxy is the same map every forge run


def run(build_dir: Path) -> dict:
    import umap

    Cw = np.load(build_dir / "centroids_whitened.npy")
    reducer = umap.UMAP(
        n_components=3,
        n_neighbors=N_NEIGHBORS,
        min_dist=MIN_DIST,
        metric="cosine",
        random_state=SEED,
        verbose=True,
    )
    coords = reducer.fit_transform(Cw).astype(np.float32)

    # Centre on the origin and scale so the cloud fits a unit-ish sphere: the
    # renderers all assume that, and it keeps the camera maths platform-free.
    coords -= coords.mean(axis=0)
    radius = float(np.percentile(np.linalg.norm(coords, axis=1), 99.5))
    coords /= max(radius, 1e-6)

    np.save(build_dir / "umap3d.npy", coords)

    stats = {
        "n_neighbors": N_NEIGHBORS,
        "min_dist": MIN_DIST,
        "seed": SEED,
        "rows": int(coords.shape[0]),
        "extent": [float(coords.min()), float(coords.max())],
        "scale_radius_p99_5": radius,
    }
    (build_dir / "stage_project.json").write_text(json.dumps(stats, indent=2))
    return stats


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    print(json.dumps(run(root / "assets/build"), indent=2))
