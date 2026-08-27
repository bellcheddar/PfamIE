"""
PfamIE Data Forge, stage 8: Core ML conversion.

Both models are wrapped so the *whole* embedding recipe lives inside the
mlpackage: tokens in, a single finished vector out. Pooling, the whitening
transform and L2 normalisation are all graph operations, which means

  - Swift never touches a 2-D MLMultiArray, so the row-padding trap that
    silently shifts every value after token 0 cannot arise here, and
  - the on-device vector is bit-comparable with the forge's, which is what
    makes the parity check at the end of this stage meaningful.

Inputs are fixed length so the Apple Neural Engine stays eligible. The caller
pads, and passes a pooling mask that already excludes BOS, EOS and padding.
"""

from __future__ import annotations

import gzip
import json
import shutil
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn

import sys as _sys; from pathlib import Path as _Path
_sys.path.insert(0, str(_Path(__file__).resolve().parent))
from model_config import PROTEIN_MODEL_ID as ESM_ID
from model_config import TEXT_MODEL_ID as MINILM_ID
ESM_LEN = 512
MINILM_LEN = 256


class WhitenedProteinEmbedder(nn.Module):
    """ESM-2 -> masked mean pool -> centre -> whiten -> L2 normalise."""

    def __init__(self, backbone, mu: np.ndarray, W: np.ndarray):
        super().__init__()
        self.backbone = backbone
        self.register_buffer("mu", torch.from_numpy(mu.astype(np.float32)))   # (1, D)
        self.register_buffer("W", torch.from_numpy(W.astype(np.float32)))     # (D, D)

    def forward(self, input_ids, attention_mask, pool_mask):
        hidden = self.backbone(
            input_ids=input_ids, attention_mask=attention_mask
        ).last_hidden_state
        m = pool_mask.unsqueeze(-1)

        # Padded query rows attend to nothing. transformers fills the mask with
        # finfo(float32).min, which is -inf once Core ML casts it to float16, so
        # those rows come back NaN and `hidden * 0` propagates NaN into the sum.
        # Select the wanted rows rather than multiplying them in.
        hidden = torch.where(m > 0, hidden, torch.zeros_like(hidden))

        pooled = hidden.sum(dim=1) / m.sum(dim=1).clamp(min=1.0)

        # L2 normalise BEFORE centring. `mu` and `W` were fitted in the forge on
        # unit-length embeddings (stage_embed normalises every sequence before
        # averaging), and the raw pooled vector has a norm around 7.8. Skipping
        # this made the centring meaningless and the whole classification
        # garbage, while torch and Core ML agreed to a cosine of 0.99999
        # because both were running the same wrong recipe.
        pooled = pooled / pooled.norm(dim=-1, keepdim=True).clamp(min=1e-9)

        v = (pooled - self.mu) @ self.W
        return v / v.norm(dim=-1, keepdim=True).clamp(min=1e-9)


class TextEmbedder(nn.Module):
    """MiniLM -> masked mean pool -> L2 normalise."""

    def __init__(self, backbone):
        super().__init__()
        self.backbone = backbone

    def forward(self, input_ids, attention_mask):
        hidden = self.backbone(
            input_ids=input_ids, attention_mask=attention_mask
        ).last_hidden_state
        m = attention_mask.unsqueeze(-1).float()
        hidden = torch.where(m > 0, hidden, torch.zeros_like(hidden))
        pooled = hidden.sum(dim=1) / m.sum(dim=1).clamp(min=1.0)
        return pooled / pooled.norm(dim=-1, keepdim=True).clamp(min=1e-9)


def _patch_transformers_masking():
    """
    transformers' and_masks/or_masks seed their fold with
    `q_idx.new_ones((), dtype=torch.bool)`. `new_ones` has no handler in either
    of coremltools' torch frontends, and it is pure ceremony: folding from the
    first mask instead of from a scalar True is the same function with one
    fewer op. Patched only inside the forge, never at runtime.
    """
    from transformers import masking_utils

    if getattr(masking_utils, "_pfamie_patched", False):
        return

    def and_masks(*mask_functions):
        def and_mask(batch_idx, head_idx, q_idx, kv_idx):
            result = None
            for mask in mask_functions:
                m = mask(batch_idx, head_idx, q_idx, kv_idx)
                result = m if result is None else (result & m.to(result.device))
            return result
        return and_mask

    def or_masks(*mask_functions):
        def or_mask(batch_idx, head_idx, q_idx, kv_idx):
            result = None
            for mask in mask_functions:
                m = mask(batch_idx, head_idx, q_idx, kv_idx)
                result = m if result is None else (result | m.to(result.device))
            return result
        return or_mask

    masking_utils.and_masks = and_masks
    masking_utils.or_masks = or_masks
    masking_utils._pfamie_patched = True


def _register_missing_ops():
    """
    coremltools 9 has no handler for `new_ones`, which transformers' masking
    helper calls to build a scalar all-true tensor. It is a one-line fill, so
    teach the converter rather than fork transformers.
    """
    from coremltools.converters.mil import Builder as mb
    from coremltools.converters.mil.frontend.torch.torch_op_registry import (
        _TORCH_OPS_REGISTRY, register_torch_op,
    )
    from coremltools.converters.mil.frontend.torch.ops import _get_inputs

    def _fill_like(context, node, value: bool):
        """
        The only callers in transformers are and_masks/or_masks, which seed a
        boolean fold with `q_idx.new_ones((), dtype=torch.bool)`. That is a
        rank-0 constant, and MIL's `fill` will not take an empty shape, so emit
        a plain const and let broadcasting do the rest.
        """
        inputs = _get_inputs(context, node)
        shape = inputs[1] if len(inputs) > 1 else None
        shape_val = getattr(shape, "val", None) if shape is not None else None

        if shape_val is None or len(np.atleast_1d(shape_val)) == 0:
            res = mb.const(val=value, name=node.name)
        else:
            dims = mb.const(val=np.asarray(shape_val, dtype=np.int32))
            res = mb.fill(shape=dims, value=1.0 if value else 0.0, name=node.name)
            res = mb.cast(x=res, dtype="bool", name=node.name + "_bool")
        context.add(res)

    # ESM's rotary attention traces `aten::Int` on a one-element shape tensor.
    # coremltools' handler does `int(x.val)` and numpy refuses that for anything
    # with a dimension, even a 1-element one. Unwrap it first.
    @register_torch_op(torch_alias=["int"], override=True)
    def _int(context, node):
        inputs = _get_inputs(context, node)
        x = inputs[0]
        if x.val is not None:
            v = np.asarray(x.val)
            if v.size == 1:
                res = mb.const(val=int(v.reshape(-1)[0]), name=node.name)
            else:
                res = mb.const(val=v.astype(np.int32), name=node.name)
        else:
            res = mb.cast(x=x, dtype="int32", name=node.name)
        context.add(res)

    if "new_ones" not in _TORCH_OPS_REGISTRY.name_to_func_mapping:
        @register_torch_op
        def new_ones(context, node):
            _fill_like(context, node, True)

    if "new_zeros" not in _TORCH_OPS_REGISTRY.name_to_func_mapping:
        @register_torch_op
        def new_zeros(context, node):
            _fill_like(context, node, False)


def _convert(wrapper, example_inputs, input_specs, out_name, out_path, palettise_bits=None):
    import coremltools as ct
    _patch_transformers_masking()
    _register_missing_ops()
    from coremltools.optimize.coreml import (
        OpPalettizerConfig, OptimizationConfig, palettize_weights,
    )

    wrapper = wrapper.eval()
    with torch.no_grad():
        traced = torch.jit.trace(wrapper, example_inputs, strict=False)

    mlmodel = ct.convert(
        traced,
        inputs=input_specs,
        outputs=[ct.TensorType(name=out_name, dtype=np.float32)],
        convert_to="mlprogram",
        compute_units=ct.ComputeUnit.ALL,
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS18,
    )

    if palettise_bits:
        cfg = OptimizationConfig(
            global_config=OpPalettizerConfig(mode="kmeans", nbits=palettise_bits)
        )
        mlmodel = palettize_weights(mlmodel, cfg)

    if out_path.exists():
        shutil.rmtree(out_path)
    mlmodel.save(str(out_path))
    return mlmodel


def convert_esm(build_dir: Path, out_dir: Path) -> dict:
    import coremltools as ct
    from transformers import AutoModel, AutoTokenizer

    mu = np.load(build_dir / "whiten_mu.npy")
    W = np.load(build_dir / "whiten_w.npy")

    # The whitening matrix has entries up to ~200, so the whitened vector has a
    # norm in the hundreds and its sum of squares exceeds float16's 65504. The
    # Neural Engine therefore returned inf for the norm and zeros for the whole
    # embedding, while the CPU path (float32 accumulation) looked perfect: the
    # exact shape of bug that ships if parity is only ever checked on CPU.
    #
    # The output is L2 normalised, so any positive scalar on W cancels
    # completely. Scale it so a typical sequence lands near unit length and
    # float16 has orders of magnitude of headroom.
    heldout = np.load(build_dir / "heldout_emb.npy")
    typical = float(np.median(np.linalg.norm((heldout - mu) @ W, axis=1)))
    w_scale = 1.0 / max(typical, 1e-9)
    W = (W * w_scale).astype(np.float32)
    backbone = AutoModel.from_pretrained(ESM_ID, attn_implementation="eager").eval()
    wrapper = WhitenedProteinEmbedder(backbone, mu, W).eval()

    ids = torch.ones(1, ESM_LEN, dtype=torch.int32)
    am = torch.ones(1, ESM_LEN, dtype=torch.int32)
    pm = torch.ones(1, ESM_LEN, dtype=torch.float32)

    specs = [
        ct.TensorType(name="input_ids", shape=(1, ESM_LEN), dtype=np.int32),
        ct.TensorType(name="attention_mask", shape=(1, ESM_LEN), dtype=np.int32),
        ct.TensorType(name="pool_mask", shape=(1, ESM_LEN), dtype=np.float32),
    ]
    # 8-bit palettisation halves t12 from 69 MB to 34 MB and, measured on the
    # Neural Engine, costs nothing in speed: 31.3 ms per window either way.
    # The end-to-end check below is what confirms it costs nothing in accuracy
    # either, so this is not taken on trust.
    out = out_dir / "PfamIEProteinEmbedder.mlpackage"
    _convert(wrapper, (ids, am, pm), specs, "embedding", out, palettise_bits=8)

    # Parity: the whole point of baking the transform in is that these agree.
    tok = AutoTokenizer.from_pretrained(ESM_ID)
    test_seq = (
        "KVFGRCELAAAMKRHGLDNYRGYSLGNWVCAAKFESNFNTQATNRNTDGSTDYGILQINSRWWCNDGRTPGS"
        "RNLCNIPCSALLSSDITASVNCAKKIVSDGNGMNAWVAWRNRCKGTDVQAWIRGCRL"
    )  # hen lysozyme, the plan's Phase 1 probe
    enc = tok(test_seq, padding="max_length", truncation=True,
              max_length=ESM_LEN, return_tensors="pt")
    pool = enc["attention_mask"].clone().float()
    pool[:, 0] = 0.0
    pool[0, int(enc["attention_mask"].sum()) - 1] = 0.0

    with torch.no_grad():
        torch_vec = wrapper(enc["input_ids"].int(), enc["attention_mask"].int(), pool).numpy()[0]

    feed = {
        "input_ids": enc["input_ids"].int().numpy(),
        "attention_mask": enc["attention_mask"].int().numpy(),
        "pool_mask": pool.numpy(),
    }

    def parity(compute_unit) -> tuple[float, float]:
        m = ct.models.MLModel(str(out), compute_units=compute_unit)
        v = np.asarray(m.predict(feed)["embedding"]).reshape(-1)
        nrm = float(np.linalg.norm(v))
        if not np.isfinite(nrm) or nrm == 0.0:
            return float("nan"), nrm
        return float(np.dot(torch_vec, v) / (np.linalg.norm(torch_vec) * nrm)), nrm

    cos_ane, norm_ane = parity(ct.ComputeUnit.ALL)
    cos_cpu, norm_cpu = parity(ct.ComputeUnit.CPU_ONLY)
    cos = cos_ane

    # A check that has only ever passed is not a check: fail the stage loudly
    # rather than shipping a model that silently returns zeros on device.
    if not (cos_ane > 0.99) or not (cos_cpu > 0.99):
        raise SystemExit(
            f"Core ML parity failed: ANE cos={cos_ane} |v|={norm_ane}, "
            f"CPU cos={cos_cpu} |v|={norm_cpu}"
        )

    return {
        "w_scale": w_scale,
        "palettise_bits": 8,
        "parity_cosine_ane": cos_ane,
        "parity_cosine_cpu": cos_cpu,
        "model": ESM_ID,
        "norm_ane": norm_ane,
        "norm_cpu": norm_cpu,
        "path": str(out),
        "sequence_length": ESM_LEN,
        "dim": int(torch_vec.shape[0]),
        "parity_cosine": cos,
        "size_mb": round(sum(f.stat().st_size for f in out.rglob("*") if f.is_file()) / 1e6, 2),
    }


def convert_minilm(out_dir: Path, palettise_bits: int | None = 8) -> dict:
    import coremltools as ct
    from transformers import AutoModel, AutoTokenizer

    backbone = AutoModel.from_pretrained(MINILM_ID, attn_implementation="eager").eval()
    wrapper = TextEmbedder(backbone).eval()

    ids = torch.ones(1, MINILM_LEN, dtype=torch.int32)
    am = torch.ones(1, MINILM_LEN, dtype=torch.int32)
    specs = [
        ct.TensorType(name="input_ids", shape=(1, MINILM_LEN), dtype=np.int32),
        ct.TensorType(name="attention_mask", shape=(1, MINILM_LEN), dtype=np.int32),
    ]
    out = out_dir / "PfamIETextEmbedder.mlpackage"
    mlmodel = _convert(wrapper, (ids, am), specs, "embedding", out,
                       palettise_bits=palettise_bits)

    tok = AutoTokenizer.from_pretrained(MINILM_ID)
    probe = "haem-binding families that dimerise"
    enc = tok(probe, padding="max_length", truncation=True,
              max_length=MINILM_LEN, return_tensors="pt")
    with torch.no_grad():
        torch_vec = wrapper(enc["input_ids"].int(), enc["attention_mask"].int()).numpy()[0]
    coreml_vec = mlmodel.predict({
        "input_ids": enc["input_ids"].int().numpy(),
        "attention_mask": enc["attention_mask"].int().numpy(),
    })["embedding"].reshape(-1)
    cos = float(np.dot(torch_vec, coreml_vec) /
                (np.linalg.norm(torch_vec) * np.linalg.norm(coreml_vec)))

    # The Swift side needs the WordPiece vocabulary to tokenise a query.
    vocab = tok.get_vocab()
    ordered = [t for t, _ in sorted(vocab.items(), key=lambda kv: kv[1])]
    (out_dir / "minilm_vocab.txt").write_text("\n".join(ordered), encoding="utf-8")

    return {
        "model": MINILM_ID,
        "path": str(out),
        "sequence_length": MINILM_LEN,
        "dim": int(torch_vec.shape[0]),
        "palettise_bits": palettise_bits,
        "parity_cosine": cos,
        "vocab_size": len(ordered),
        "size_mb": round(sum(f.stat().st_size for f in out.rglob("*") if f.is_file()) / 1e6, 2),
    }


def export_esm_vocab(out_dir: Path) -> dict:
    """ESM-2's alphabet is 33 tokens, so Swift can hold it as a literal table."""
    from transformers import AutoTokenizer

    tok = AutoTokenizer.from_pretrained(ESM_ID)
    vocab = tok.get_vocab()
    ordered = [t for t, _ in sorted(vocab.items(), key=lambda kv: kv[1])]
    spec = {
        "tokens": ordered,
        "cls_token_id": tok.cls_token_id,
        "eos_token_id": tok.eos_token_id,
        "pad_token_id": tok.pad_token_id,
        "unk_token_id": tok.unk_token_id,
        "mask_token_id": tok.mask_token_id,
    }
    (out_dir / "esm2_vocab.json").write_text(json.dumps(spec, indent=2))
    return {"vocab_size": len(ordered), **{k: v for k, v in spec.items() if k != "tokens"}}


def verify_against_index(build_dir: Path, out_dir: Path, sample: int = 200) -> dict:
    """
    Embed real held-out seed sequences through the *converted* model and look
    them up in the shipped centroid matrix.

    Parity against the torch wrapper only proves the two agree; it cannot
    notice that both implement the same wrong recipe. This measures where the
    vector actually lands, and is the check that catches a broken preprocessing
    step. Top-1 here should sit near the calibrated 0.71.
    """
    import coremltools as ct
    from transformers import AutoTokenizer

    families = json.loads(
        gzip.open(build_dir / "families.json.gz", "rt", encoding="utf-8").read()
    )
    Cw = np.load(build_dir / "centroids_whitened.npy")
    tok = AutoTokenizer.from_pretrained(ESM_ID)
    model = ct.models.MLModel(str(out_dir / "PfamIEProteinEmbedder.mlpackage"))

    rng = np.random.default_rng(0)
    candidates = [i for i, f in enumerate(families) if f["heldout_seqs"]]
    chosen = rng.choice(len(candidates), size=min(sample, len(candidates)), replace=False)

    hits1 = hits5 = tested = 0
    for pick in chosen:
        row = candidates[int(pick)]
        seq = families[row]["heldout_seqs"][0]["sequence"]
        enc = tok(seq, padding="max_length", truncation=True,
                  max_length=ESM_LEN, return_tensors="np")
        am = enc["attention_mask"].astype(np.int32)
        pool = am.astype(np.float32).copy()
        pool[:, 0] = 0.0
        pool[0, int(am.sum()) - 1] = 0.0
        v = np.asarray(model.predict({
            "input_ids": enc["input_ids"].astype(np.int32),
            "attention_mask": am,
            "pool_mask": pool,
        })["embedding"]).reshape(-1)
        order = np.argsort(-(Cw @ v))[:5]
        hits1 += int(order[0] == row)
        hits5 += int(row in order)
        tested += 1

    result = {
        "sampled": tested,
        "top1": hits1 / max(tested, 1),
        "top5": hits5 / max(tested, 1),
    }
    if result["top1"] < 0.55:
        raise SystemExit(
            f"Converted model does not land where it should: top1={result['top1']:.3f} "
            f"over {tested} held-out sequences (expected ~0.71)."
        )
    return result


def run(build_dir: Path, out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    stats = {
        "esm_vocab": export_esm_vocab(out_dir),
        "protein_embedder": convert_esm(build_dir, out_dir),
        "text_embedder": convert_minilm(out_dir),
    }
    stats["end_to_end"] = verify_against_index(build_dir, out_dir)
    (build_dir / "stage_coreml.json").write_text(json.dumps(stats, indent=2))
    return stats


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    print(json.dumps(run(root / "assets/build", root / "assets/coreml"), indent=2))
