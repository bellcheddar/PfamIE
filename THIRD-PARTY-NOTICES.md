# Third-party notices

PfamIE itself is MIT licensed (see `LICENSE`). MIT was chosen because it is
compatible with everything the app bundles, and because the two model weights
it ships are themselves MIT and Apache-2.0. Nothing in the bundle carries a
copyleft or non-commercial term.

Each component below keeps its own licence. This file is the attribution those
licences require; it is not a re-licensing of them.

## Bundled in the shipped app

| Component | Version | Licence | What we ship |
|---|---|---|---|
| [ESM-2](https://huggingface.co/facebook/esm2_t6_8M_UR50D) `t6_8M_UR50D` | 2022 release | MIT, Meta Platforms | The weights, converted to Core ML and quantised to float16. Modified: masked mean pooling, a whitening transform and L2 normalisation are compiled into the graph. |
| [all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) | 2021 release | Apache-2.0, UKP Lab / sentence-transformers | The weights, converted to Core ML and palettised to 8 bits. Modified: mean pooling and L2 normalisation are compiled into the graph. The WordPiece vocabulary ships verbatim. |
| [Mol\*](https://molstar.org/) | 4.9.0 | MIT, Mol\* contributors | The single-file viewer build, unmodified. |
| [Pfam](https://www.ebi.ac.uk/interpro/) | 38.2 | **CC0 1.0** (public domain dedication), the Pfam consortium | Family metadata, clan assignments, abstracts and seed-derived representative sequences. |
| [InterPro](https://www.ebi.ac.uk/interpro/) | current | EMBL-EBI, freely available | Domain architectures, family sizes and taxonomic breadth. |

### Apache-2.0 notice for all-MiniLM-L6-v2

Licensed under the Apache License, Version 2.0. You may obtain a copy at
<http://www.apache.org/licenses/LICENSE-2.0>. The weights distributed in this
app have been **modified** from the original: converted to the Core ML format,
palettised to 8-bit, and wrapped so that mean pooling and L2 normalisation
occur inside the model graph rather than in calling code.

### Pfam and CC0

The Pfam consortium has dedicated Pfam to the public domain under CC0 1.0, so
no attribution is legally required. It is given here anyway, because a tool
that makes claims about protein families should say where those families came
from.

## Fetched at runtime, never redistributed

| Source | Licence | Use |
|---|---|---|
| [AlphaFold DB](https://alphafold.ebi.ac.uk/) | CC-BY 4.0, DeepMind and EMBL-EBI | Predicted structures, downloaded on demand and cached on the device. No AlphaFold model is included in the app bundle. |
| [UniProt](https://www.uniprot.org/) | CC-BY 4.0 | Sequences used to build the benchmark and calibration sets during the forge. Not shipped. |

## Build-time only, not shipped

PyTorch (BSD-3-Clause), Hugging Face Transformers (Apache-2.0), coremltools
(BSD-3-Clause), umap-learn (BSD-3-Clause), scikit-learn (BSD-3-Clause), NumPy
(BSD-3-Clause) and Pillow (MIT-CMU) are used by `forge/` to build the assets
and form no part of the distributed application.

## How to cite the science

If PfamIE contributes to published work, cite the underlying resources rather
than this app:

- Mistry J. *et al.* **Pfam: The protein families database in 2021.** *Nucleic Acids Research* 49:D412-D419 (2021).
- Lin Z. *et al.* **Evolutionary-scale prediction of atomic-level protein structure with a language model.** *Science* 379:1123-1130 (2023).
- Varadi M. *et al.* **AlphaFold Protein Structure Database.** *Nucleic Acids Research* 52:D368-D375 (2024).
- Sehnal D. *et al.* **Mol\* Viewer: modern web app for 3D visualization and analysis of large biomolecular structures.** *Nucleic Acids Research* 49:W431-W437 (2021).
