"""
What does the bigger model cost on the Neural Engine?

t12-35M buys +4.1 points of real-protein top-1. Whether that is worth taking
depends on inference time, because the Oracle scans 33 windows for a
500-residue protein and the app's whole premise is that this feels instant.
FLOPs alone predict about 4.5x, but the ANE is not a FLOP machine and the only
honest way to know is to convert it and time it.
"""

from __future__ import annotations

import json
import shutil
import sys
import time
from pathlib import Path

import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from stage_coreml import (ESM_LEN, WhitenedProteinEmbedder, _patch_transformers_masking,
                          _register_missing_ops)

MODEL_ID = "facebook/esm2_t12_35M_UR50D"


def main():
    import coremltools as ct
    from coremltools.optimize.coreml import (OpPalettizerConfig, OptimizationConfig,
                                             palettize_weights)
    from transformers import AutoModel, AutoTokenizer

    root = Path(__file__).resolve().parent.parent
    build = root / "assets/build_t12"
    out = root / "assets/coreml_t12"
    out.mkdir(parents=True, exist_ok=True)

    mu = np.load(build / "whiten_mu.npy")
    W = np.load(build / "whiten_w.npy")
    heldout = np.load(build / "heldout_emb.npy")
    typical = float(np.median(np.linalg.norm((heldout - mu) @ W, axis=1)))
    W = (W / max(typical, 1e-9)).astype(np.float32)

    _patch_transformers_masking()
    backbone = AutoModel.from_pretrained(MODEL_ID, attn_implementation="eager").eval()
    wrapper = WhitenedProteinEmbedder(backbone, mu, W).eval()

    ids = torch.ones(1, ESM_LEN, dtype=torch.int32)
    am = torch.ones(1, ESM_LEN, dtype=torch.int32)
    pm = torch.ones(1, ESM_LEN, dtype=torch.float32)

    _register_missing_ops()
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, (ids, am, pm), strict=False)

    results = {}
    for label, bits in (("float16", None), ("palettised8", 8)):
        model = ct.convert(
            traced,
            inputs=[
                ct.TensorType(name="input_ids", shape=(1, ESM_LEN), dtype=np.int32),
                ct.TensorType(name="attention_mask", shape=(1, ESM_LEN), dtype=np.int32),
                ct.TensorType(name="pool_mask", shape=(1, ESM_LEN), dtype=np.float32),
            ],
            outputs=[ct.TensorType(name="embedding", dtype=np.float32)],
            convert_to="mlprogram",
            compute_units=ct.ComputeUnit.ALL,
            compute_precision=ct.precision.FLOAT16,
            minimum_deployment_target=ct.target.iOS18,
        )
        if bits:
            model = palettize_weights(model, OptimizationConfig(
                global_config=OpPalettizerConfig(mode="kmeans", nbits=bits)))

        path = out / f"PfamIEProteinEmbedder_t12_{label}.mlpackage"
        if path.exists():
            shutil.rmtree(path)
        model.save(str(path))
        size = sum(f.stat().st_size for f in path.rglob("*") if f.is_file()) / 1e6

        tok = AutoTokenizer.from_pretrained(MODEL_ID)
        seq = ("KVFGRCELAAAMKRHGLDNYRGYSLGNWVCAAKFESNFNTQATNRNTDGSTDYGILQINSRWWCNDGRTPGS"
               "RNLCNIPCSALLSSDITASVNCAKKIVSDGNGMNAWVAWRNRCKGTDVQAWIRGCRL")
        enc = tok(seq, padding="max_length", truncation=True,
                  max_length=ESM_LEN, return_tensors="np")
        amask = enc["attention_mask"].astype(np.int32)
        pool = amask.astype(np.float32).copy()
        pool[:, 0] = 0.0
        pool[0, int(amask.sum()) - 1] = 0.0
        feed = {"input_ids": enc["input_ids"].astype(np.int32),
                "attention_mask": amask, "pool_mask": pool}

        timings = {}
        for unit_name, unit in (("ane", ct.ComputeUnit.ALL), ("cpu", ct.ComputeUnit.CPU_ONLY)):
            m = ct.models.MLModel(str(path), compute_units=unit)
            v = np.asarray(m.predict(feed)["embedding"]).reshape(-1)
            norm = float(np.linalg.norm(v))
            started = time.time()
            rounds = 25
            for _ in range(rounds):
                m.predict(feed)
            timings[unit_name] = (time.time() - started) / rounds * 1000
            timings[f"{unit_name}_norm"] = norm

        results[label] = {"size_mb": round(size, 2), **{k: round(v, 3) for k, v in timings.items()}}
        print(f"{label}: {json.dumps(results[label])}", file=sys.stderr)

    (build / "latency.json").write_text(json.dumps(results, indent=2))
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
