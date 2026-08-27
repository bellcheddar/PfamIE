"""
PfamIE Data Forge, stage 6: description embeddings for the Field Guide.

MiniLM-L6-v2 over each family's abstract, so "haem-binding families that
dimerise" finds something sensible with no network. The same model ships as a
Core ML package, because the query has to be embedded on device.
"""

from __future__ import annotations

import gzip
import json
import time
from pathlib import Path

import numpy as np
import torch
from transformers import AutoModel, AutoTokenizer

MODEL_ID = "sentence-transformers/all-MiniLM-L6-v2"
MAX_TOKENS = 256          # abstracts are short; 256 covers 99% of them
BATCH = 128


def _device() -> torch.device:
    return torch.device("mps") if torch.backends.mps.is_available() else torch.device("cpu")


def searchable_text(fam: dict) -> str:
    """
    What the Field Guide actually searches. The identifier and clan name carry
    a surprising amount of signal ("Peptidase_S8", "Glyco_hydro_5"), so they go
    in front of the abstract rather than being left to the metadata filter.
    """
    parts = [fam["identifier"].replace("_", " "), fam["description"]]
    if fam.get("clan_description"):
        parts.append(fam["clan_description"])
    if fam["abstract"]:
        parts.append(fam["abstract"])
    return ". ".join(p for p in parts if p)[:4000]


@torch.no_grad()
def embed_texts(texts: list[str]) -> np.ndarray:
    device = _device()
    tok = AutoTokenizer.from_pretrained(MODEL_ID)
    model = AutoModel.from_pretrained(MODEL_ID).eval().to(device)

    out = np.zeros((len(texts), model.config.hidden_size), dtype=np.float32)
    started = time.time()
    for i in range(0, len(texts), BATCH):
        batch = texts[i : i + BATCH]
        enc = tok(batch, padding="max_length", truncation=True,
                  max_length=MAX_TOKENS, return_tensors="pt").to(device)
        hidden = model(**enc).last_hidden_state
        mask = enc["attention_mask"].unsqueeze(-1).to(hidden.dtype)
        pooled = (hidden * mask).sum(1) / mask.sum(1).clamp(min=1)
        pooled = torch.nn.functional.normalize(pooled, dim=-1)
        out[i : i + len(batch)] = pooled.float().cpu().numpy()
        if (i // BATCH) % 20 == 0:
            rate = (i + len(batch)) / max(time.time() - started, 1e-6)
            print(f"\rdescemb: {i+len(batch)}/{len(texts)}  {rate:.0f}/s", end="", flush=True)
    print()
    return out


def run(build_dir: Path) -> dict:
    families = json.loads(
        gzip.open(build_dir / "families.json.gz", "rt", encoding="utf-8").read()
    )
    texts = [searchable_text(f) for f in families]
    emb = embed_texts(texts)
    np.save(build_dir / "desc_emb.npy", emb)

    stats = {
        "model": MODEL_ID,
        "dim": int(emb.shape[1]),
        "rows": int(emb.shape[0]),
        "max_tokens": MAX_TOKENS,
        "mean_text_chars": int(np.mean([len(t) for t in texts])),
    }
    (build_dir / "stage_descemb.json").write_text(json.dumps(stats, indent=2))
    return stats


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    print(json.dumps(run(root / "assets/build"), indent=2))
