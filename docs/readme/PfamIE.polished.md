# 🧬 PfamIE

> **The entire Pfam universe as an on-device inference engine: paste a sequence, get a family, offline.**

![swift](https://img.shields.io/badge/swift-6.3-F05138?logo=swift&logoColor=white) ![platforms](https://img.shields.io/badge/platforms-iOS%20%C2%B7%20iPadOS%20%C2%B7%20macOS%20%C2%B7%20visionOS%20%C2%B7%20watchOS-000000?logo=apple&logoColor=white) ![xcode](https://img.shields.io/badge/xcode-26.6-1575F9?logo=xcode&logoColor=white) ![coreml](https://img.shields.io/badge/Core%20ML-Neural%20Engine-0A84FF?logo=apple&logoColor=white) ![esm2](https://img.shields.io/badge/ESM--2-t6%208M-5EEAD4) ![minilm](https://img.shields.io/badge/MiniLM-L6--v2-A78BFA) ![accelerate](https://img.shields.io/badge/Accelerate-vDSP%20%C2%B7%20BLAS-FB923C) ![molstar](https://img.shields.io/badge/Mol*-4.9.0-4C6EF5) ![sqlite](https://img.shields.io/badge/SQLite-FTS5-003B57?logo=sqlite&logoColor=white) ![python](https://img.shields.io/badge/python-3.12.13-3776AB?logo=python&logoColor=white) ![torch](https://img.shields.io/badge/pytorch-2.13.0-EE4C2C?logo=pytorch&logoColor=white) ![transformers](https://img.shields.io/badge/transformers-5.16.1-FFD21E?logo=huggingface&logoColor=black) ![coremltools](https://img.shields.io/badge/coremltools-9.0-555555) ![umap](https://img.shields.io/badge/umap--learn-0.5.12-9b51e0) ![tests](https://img.shields.io/badge/tests-17%20passing-00897B) ![data](https://img.shields.io/badge/data-Pfam%2038.2%20%C2%B7%20InterPro%20%C2%B7%20UniProt%20%C2%B7%20AlphaFold-467FF7) ![offline](https://img.shields.io/badge/classification-100%25%20offline-00d084) ![phase](https://img.shields.io/badge/phase-1.0%20build%20complete-fcb900) ![licence](https://img.shields.io/badge/licence-see%20below-lightgrey) ![author](https://img.shields.io/badge/author-Marc%20C.%20Deller%2C%20D.Phil.-1C244B)

<table>
<tr>
<td>🌐 <b>Website</b></td><td><a href="https://marcdeller.com" target="_blank" rel="noopener noreferrer">marcdeller.com</a></td>
<td>✉️ <b>Contact</b></td><td><a href="mailto:marc@marcdeller.com">marc@marcdeller.com</a></td>
<td>🐙 <b>GitHub</b></td><td><a href="https://github.com/bellcheddar/PfamIE" target="_blank" rel="noopener noreferrer">bellcheddar/PfamIE</a></td>
</tr>
</table>

---

PfamIE turns all 30,031 Pfam families into an inference engine that fits in your pocket. A quantised ESM-2 protein language model runs on the Apple Neural Engine, embeds any sequence you paste, and classifies it against a pre-baked matrix of family centroid embeddings: family assignment with no HMM, no server, and no network. Around that core sit five views: a 3D flythrough map of the whole Pfam universe, a sequence oracle with a calibrated confidence, a domain-architecture explorer, a browser for the dark proteome, and an offline atlas you can search in plain English.

**Why it matters:** every existing route to a Pfam assignment goes through a server. HMMER against Pfam-A means a web queue or a local install and a 1.5 GB HMM library, and neither works on a train, in a hospital, at a conference, or anywhere the sequence in front of you is not yours to upload. PfamIE puts the whole search space on the device, answers in a second and a half, and tells you honestly how often it is wrong. It is useful for anyone who wants a first-pass family call, a domain architecture, or a functional lead for an uncharacterised protein: bench scientists triaging a hit, structural biologists sizing up a construct, and teachers who want the shape of protein sequence space on a screen they can spin.

---

## ✨ What it does

| Tab | What it is for |
|---|---|
| **Galaxy** | All 30,031 families as a 3D point cloud, clans as coloured regions, the dark proteome drawn dim. Tap a star, open its card, or watch your last query drop in as an amber comet. |
| **Oracle** | Paste a sequence or open a FASTA. Multi-scale window scanning returns the family, the clan, the N-to-C domain architecture, and a confidence that has been calibrated against real proteins. |
| **Grammarian** | Which domains travel with which, in what order, and how often: co-occurrence graphs over 199,143 real architectures, and "what else is built like mine?" |
| **Prospector** | The 7,874 families with no known function, each with its nearest annotated neighbours as an explicitly hypothesis-flavoured lead. |
| **Field Guide** | The offline Pfam atlas. "breaks down plastic" and "haem-binding families that dimerise" both work, with no network, through a bundled MiniLM. |

Every family reference anywhere in the app carries the same four actions (**Open card · Show in Galaxy · Similar architectures · View structure**), so no tab is a dead end. Any family can open an AlphaFold model with its Pfam domain highlighted: AlphaFold uses UniProt numbering, so Pfam boundaries map onto the structure with no residue-mapping step.

## 📊 How well it works

This is the part most tools leave out, so it goes near the top.

Measured on **2,500 real single-domain UniProt proteins**, ranked against all 30,031 families, with thresholds fitted on 1,875 and every accuracy below reported on the 625 held back:

| Confidence band | Share of queries | Correct |
|---|---|---|
| **High** (p ≥ 0.75) | 22.7% | **94.4%** |
| **Moderate** (p ≥ 0.45) | 19.7% | 55.3% |
| **Low** (p ≥ 0.25) | 25.9% | 30.9% |
| **No confident family** (p < 0.25) | 31.7% | 9.6% |

Overall top-1 is 0.43, top-5 0.49 and top-20 0.55. The app abstains on roughly a third of queries rather than naming the least-bad of 30,031 options.

**Why the headline number is not 0.72.** Held-out Pfam seed sequences score 0.72 top-1 on exactly the same pipeline, and that is the number this README could have quoted. It would have been misleading: seed sequences are trimmed to domain boundaries and drawn from the very alignments the centroids were built from, so they measure the index against its own kind. Real proteins carry signal peptides, linkers, disordered tails and other domains. Calibrated on seeds, an all-alanine nonsense sequence came back at 0.51 confidence; calibrated on real proteins it comes back at 0.28. Both figures are in Settings, labelled.

**Scanning strategy, measured on 400 real proteins:**

| Approach | Top-1 | Top-5 |
|---|---|---|
| Whole sequence embedded end to end | 0.285 | 0.435 |
| One 160-residue sliding window | 0.425 | 0.548 |
| Four widths: 96 / 160 / 256 / 384 | **0.535** | **0.635** |

No single window width fits Pfam, whose domains run from about 30 residues to several hundred. Multi-scale costs inference time and nothing in bundle size.

## 🧱 How it is built

```
PfamIE/
├── forge/                Python: builds every asset the app ships (Phase 0)
├── PfamIEKit/            SwiftPM package: engine, data, and all shared views
│   └── Sources/PfamIEKit/
│       ├── Engine/       tokenisers, Core ML embedders, centroid index, domain scanner
│       ├── Data/         SQLite store, AlphaFold client, models
│       ├── Core/         engine facade, router, theme, app environment
│       └── Views/        Galaxy, Oracle, Grammarian, Prospector, Field Guide, Structure
├── Apps/                 thin per-platform targets
│   ├── iOS/              iPhone tabs and iPad three-column, one target
│   ├── macOS/            native SwiftUI, sidebar, menu commands, FASTA on the dock icon
│   ├── visionOS/         volumetric Galaxy plus windowed tabs
│   └── watchOS/          companion glance over WatchConnectivity
├── Tools/                project generation and bundle verification
└── project.yml           XcodeGen spec: the .xcodeproj is derived, never hand-edited
```

All five platforms share one engine. `PfamIEKit` imports no UIKit or AppKit anywhere except the two files behind the structure viewer, which need a web view and say so.

| Component | Notes |
|---|---|
| `ProteinEmbedder` | ESM-2 t6-8M as Core ML, fixed 512 tokens, Neural Engine eligible. Pooling, whitening and normalisation are all graph operations, so the output is a finished unit vector and Swift never indexes a 2-D `MLMultiArray`. |
| `Float16Matrix` | Memory-mapped float16 matrices with a chunked Accelerate `sgemv`. Top-20 over 30,031 families in **1.5 ms**. |
| `DomainScanner` | Multi-scale windows, per-scale merging, then greedy non-overlapping selection by confidence. |
| `SemanticSearch` | MiniLM-L6-v2 as Core ML plus a Swift WordPiece tokeniser, over 30,031 description embeddings. |
| `PfamStore` | Raw sqlite3, no wrapper library. FTS5 for literal search, running alongside the semantic search rather than instead of it. |
| `Router` | One closed `Destination` enum. Every context menu, every deep link and every card action resolves to a case of it. |

## ⚗️ The forge (Phase 0)

`forge/` builds everything the app ships, from the Pfam 38.2 release flatfiles and the InterPro API. Run it before building the app.

```bash
python3.12 -m venv .venv
.venv/bin/pip install -r forge/requirements.txt

# Pfam release flatfiles (about 54 MB)
mkdir -p assets/raw && cd assets/raw
for f in Pfam-A.clans.tsv.gz Pfam-C.gz Pfam-A.hmm.dat.gz Pfam-A.seed.gz; do
  curl -sLO "https://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/$f"
done
cd ../..

.venv/bin/python forge/stage_metadata.py        # families, clans, representative sequences
.venv/bin/python forge/stage_interpro.py ida    # domain architectures (about 100 min)
.venv/bin/python forge/stage_interpro.py counters
.venv/bin/python forge/stage_embed.py           # ESM-2 over 368,451 sequences
.venv/bin/python forge/stage_transform.py       # whitening and seed calibration
.venv/bin/python forge/stage_project.py         # 3D UMAP for the Galaxy
.venv/bin/python forge/stage_descemb.py         # MiniLM over every abstract
.venv/bin/python forge/stage_coreml.py          # Core ML conversion and parity checks
.venv/bin/python forge/stage_calibrate_real.py  # confidence, fitted on real proteins
.venv/bin/python forge/stage_sqlite.py
.venv/bin/python forge/stage_emit.py
```

| Stage | Produces |
|---|---|
| `stage_metadata` | 30,031 families, 891 clans, 7,874 DUFs, a UniProt structural representative for every family |
| `stage_interpro` | 199,143 distinct N-to-C architectures and 208,401 co-occurrence edges |
| `stage_embed` | 368,451 ESM-2 embeddings, 16 stratified seed sequences per family centroid |
| `stage_transform` | The 320 × 320 whitening transform, and the seed-based reference calibration |
| `stage_coreml` | Two `.mlpackage` models, with parity asserted on the Neural Engine and end to end against the index |
| `stage_calibrate_real` | The shipped temperature and confidence bands |
| `stage_emit` | `centroids.bin`, `umap3d.bin`, `desc_emb.bin`, `manifest.json` |

**Two findings the forge exists to prevent from recurring**, both recorded in the code that catches them:

- **Anisotropy.** Mean-pooled ESM-2 embeddings put every family at cosine ~0.97 to every other, and short families collapse into a single hub. Whitening the centroid covariance lifts held-out top-1 from 0.514 to 0.715 and pulls the mean nearest-neighbour cosine from 0.968 to 0.677. Without it, the Galaxy is a featureless ball and the Oracle is a coin toss.
- **Parity is not correctness.** The Core ML model whitened the un-normalised pooled vector while `mu` and `W` had been fitted on unit-length ones. Torch and Core ML agreed to a cosine of 0.99999 the entire time, because both were running the same wrong recipe, and lysozyme classified as a coiled coil. The forge now embeds held-out sequences through the *converted* model and looks them up in the *shipped* index, which is the check that catches it.

## 🔧 Building the app

```bash
brew install xcodegen
./Tools/generate-project.sh                 # regenerates PfamIE.xcodeproj from project.yml
open PfamIE.xcodeproj

# Or from the command line:
xcodebuild -project PfamIE.xcodeproj -scheme PfamIE-macOS -destination 'platform=macOS' build
swift test -c release --package-path PfamIEKit
```

Tests need the forge output. Without it the asset-dependent suites skip rather than fail, so a fresh clone still runs green.

**Always verify a built bundle before shipping it.** `BUILD SUCCEEDED` says nothing about the contents, and an app missing its Core ML models builds and signs perfectly:

```bash
./Tools/verify-bundle.sh ~/Library/Developer/Xcode/DerivedData/PfamIE-*/Build/Products/Debug/PfamIE.app
```

The script is negative-tested: strip a model from a copy of the bundle and it must exit 1.

## 📋 Requirements

| | |
|---|---|
| Xcode | 26.6 or later |
| Deployment | iOS 18, macOS 15, visionOS 2, watchOS 11 |
| Forge | Python 3.12 (numba and coremltools are not yet reliable on 3.14) |
| Bundle | About 170 MB: 83 MB database, 40 MB matrices, 39 MB models, 5 MB Mol\* |
| Network | Only for AlphaFold structures. Classification, architecture and search are entirely offline. |

## ✅ To Do

Roadmap for PfamIE, in dependency order. Suggestions welcome.

- [x] **Phase 0: the data forge.** Reads the Pfam 38.2 flatfiles offline rather than making 30,031 API calls, so all metadata, clans, abstracts and representative sequences come from one 52 MB download. Only architectures and family sizes need InterPro.
- [x] **Whitening the centroid space.** Measured, not assumed: held-out top-1 0.514 → 0.715, and the nearest-neighbour cosine 0.968 → 0.677. A shrinkage sweep found the plateau at eps 1e-5, which also caps eigen-amplification at a conservative 34×.
- [x] **Stratified centroid sequences.** Choosing the sequences closest to the median seed length looked sensible and selected near-duplicates: PF00062 got six α-lactalbumins out of eight and could not recognise hen lysozyme. An even sweep across the alignment costs nothing and spans the family; lysozyme went from rank 42 to rank 2.
- [x] **Core ML conversion with parity asserted on the Neural Engine.** The whitened vector's sum of squares overflows float16 in the norm reduction, so the ANE returned all zeros while the CPU path looked perfect. Scaling `W` is free because the output is L2 normalised. Parity is now checked on `ComputeUnit.ALL`, and the stage fails rather than shipping a silent zero.
- [x] **Phase 1: engine.** Memory-mapped float16 matrices, chunked Accelerate gemv at 1.5 ms per query, raw sqlite3 store, Swift ESM-2 and WordPiece tokenisers.
- [x] **Multi-scale domain scanning.** Whole-sequence embedding turned out to be the *weakest* signal on real proteins (0.285 top-1). Four window widths give 0.535 at no bundle cost.
- [x] **Confidence calibrated on real proteins.** Not on held-out seed sequences, which overstate accuracy by about 30 points. A test fails the build if the shipped calibration ever matches the seed-fitted one.
- [x] **Phase 2 and 3: five tabs.** Galaxy, Oracle, Grammarian, Prospector, Field Guide, plus the universal family card and the closed-enum router.
- [x] **Structure layer.** Bundled Mol\*, AlphaFold mmCIF with disk caching, domain highlighting in UniProt numbering, and a quiet offline note rather than a spinner that never resolves.
- [x] **Bundle verification, negative-tested.** `Tools/verify-bundle.sh` checks every model, matrix and database, and is proven to fail when one is removed.
- [ ] **visionOS and watchOS build verification.** Both targets are written and the SDKs are present, but the platform components are still downloading, so neither has been compiled yet. Nothing else is blocking them.
- [ ] **App icon.** Placeholder only. Note that the App Store rejects an icon with an alpha channel, and PIL hands you RGBA by default.
- [ ] **Trim the bundle.** 170 MB against a 60 MB target. int8 per-row quantisation of the centroids is free (top-1 0.7150 against 0.7149 at float16) and halves them to 9.6 MB; the same for the description embeddings saves 11.5 MB. The 83 MB database is the real target: capping architectures per family is the lever.
- [ ] **A larger protein model.** ESM-2 t6-8M is 8 million parameters, and 0.43 top-1 on real proteins is its honest ceiling. t12-35M is the obvious next step, at roughly +35 MB palettised, and should be measured on the same real-protein benchmark rather than on held-out seeds.
- [ ] **Boundary refinement.** Domain calls are resolved to about a third of a window width. A second pass at finer stride around each accepted boundary would sharpen the architecture track.
- [ ] **VisionKit sequence scanning.** Read a printed sequence with the camera. First on the cut list and duly cut.
- [ ] **HMMER verification.** An optional, clearly labelled network path to check a call against the real thing at EBI.
- [ ] **watchOS complication.** The synced glance view is built; the complication is not.
- [ ] **Licence.** Add your licence here.

## 🔬 Data sources

| Source | Used for |
|---|---|
| [Pfam 38.2](https://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/) | Family metadata, clans, abstracts, seed alignments |
| [InterPro API](https://www.ebi.ac.uk/interpro/) | Domain architectures, family sizes, taxonomic breadth |
| [UniProt](https://www.uniprot.org/) | Benchmark and calibration sequences |
| [AlphaFold DB](https://alphafold.ebi.ac.uk/) | Predicted structures, fetched on demand and cached |
| [ESM-2](https://huggingface.co/facebook/esm2_t6_8M_UR50D) | Protein sequence embeddings |
| [MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) | Description embeddings for offline semantic search |
| [Mol\*](https://molstar.org/) | Structure rendering |

---

## 👤 Author

**Marc C. Deller, D.Phil.**  
Structural biologist & drug discovery scientist  

<table>
<tr>
<td>🌐</td><td><a href="https://marcdeller.com" target="_blank" rel="noopener noreferrer">marcdeller.com</a></td>
<td>✉️</td><td><a href="mailto:marc@marcdeller.com">marc@marcdeller.com</a></td>
<td>🐙</td><td><a href="https://github.com/bellcheddar/PfamIE" target="_blank" rel="noopener noreferrer">github.com/bellcheddar/PfamIE</a></td>
</tr>
</table>
