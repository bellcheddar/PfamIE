# 🧬 PfamIE

> **The entire Pfam universe as an on-device inference engine: paste a sequence, get a family, offline.**

![swift](https://img.shields.io/badge/swift-6.3-F05138?logo=swift&logoColor=white) ![platforms](https://img.shields.io/badge/platforms-iOS%20%C2%B7%20iPadOS%20%C2%B7%20macOS%20%C2%B7%20visionOS%20%C2%B7%20watchOS-000000?logo=apple&logoColor=white) ![xcode](https://img.shields.io/badge/xcode-26.6-1575F9?logo=xcode&logoColor=white) ![ane](https://img.shields.io/badge/Neural%20Engine-2.4x%20over%20CPU-0A84FF?logo=apple&logoColor=white) ![coreml](https://img.shields.io/badge/Core%20ML-float16%20%C2%B7%208--bit%20palettised-555555) ![esm2](https://img.shields.io/badge/ESM--2-t12%2035M-5EEAD4) ![minilm](https://img.shields.io/badge/MiniLM-L6--v2-A78BFA) ![accelerate](https://img.shields.io/badge/Accelerate-vDSP%20%C2%B7%20BLAS-FB923C) ![realitykit](https://img.shields.io/badge/RealityKit-volumetric-8B5CF6) ![molstar](https://img.shields.io/badge/Mol*-4.9.0-4C6EF5) ![sqlite](https://img.shields.io/badge/SQLite-FTS5-003B57?logo=sqlite&logoColor=white) ![python](https://img.shields.io/badge/python-3.12.13-3776AB?logo=python&logoColor=white) ![torch](https://img.shields.io/badge/pytorch-2.13.0-EE4C2C?logo=pytorch&logoColor=white) ![transformers](https://img.shields.io/badge/transformers-5.16.1-FFD21E?logo=huggingface&logoColor=black) ![coremltools](https://img.shields.io/badge/coremltools-9.0-777777) ![umap](https://img.shields.io/badge/umap--learn-0.5.12-9b51e0) ![tests](https://img.shields.io/badge/tests-34%20passing-00897B) ![data](https://img.shields.io/badge/data-Pfam%2038.2%20%C2%B7%20InterPro%20%C2%B7%20UniProt%20%C2%B7%20AlphaFold-467FF7) ![offline](https://img.shields.io/badge/inference-100%25%20on%20device-00d084) ![licence](https://img.shields.io/badge/licence-MIT-1C7D3E) ![author](https://img.shields.io/badge/author-Marc%20C.%20Deller%2C%20D.Phil.-1C244B)

<table>
<tr>
<td>🌐 <b>Website</b></td><td><a href="https://marcdeller.com" target="_blank" rel="noopener noreferrer">marcdeller.com</a></td>
<td>✉️ <b>Contact</b></td><td><a href="mailto:marc@marcdeller.com">marc@marcdeller.com</a></td>
<td>🐙 <b>GitHub</b></td><td><a href="https://github.com/bellcheddar/PfamIE" target="_blank" rel="noopener noreferrer">bellcheddar/PfamIE</a></td>
</tr>
</table>

---

PfamIE turns all 30,031 Pfam families into an inference engine that fits in your pocket. A quantised ESM-2 protein language model runs on the Apple Neural Engine, embeds any sequence you paste, and classifies it against a pre-baked matrix of family centroid embeddings: family assignment with no HMM, no server, and no network. Around that core sit five views, from a 3D flythrough of the whole Pfam universe to an offline atlas you can search in plain English.

**Why it matters:** every existing route to a Pfam assignment goes through a server. HMMER against Pfam-A means a web queue or a local install and a 1.5 GB HMM library, and neither works on a train, in a hospital, at a conference, or anywhere the sequence in front of you is not yours to upload. PfamIE puts the whole search space on the device, answers a 536-residue protein in about a second, and states how often it is wrong rather than leaving you to guess. It is useful for anyone who wants a first-pass family call, a domain architecture, or a functional lead for an uncharacterised protein: bench scientists triaging a hit, structural biologists sizing up a construct, and teachers who want the shape of protein sequence space on a screen they can spin.

---

## 📸 What it looks like

<table>
<tr>
<td width="33%"><img src="https://raw.githubusercontent.com/bellcheddar/PfamIE/main/docs/screenshots/galaxy.png" alt="The Galaxy: all 30,031 Pfam families as a 3D point cloud"></td>
<td width="33%"><img src="https://raw.githubusercontent.com/bellcheddar/PfamIE/main/docs/screenshots/oracle.png" alt="The Oracle classifying human SRC kinase"></td>
<td width="33%"><img src="https://raw.githubusercontent.com/bellcheddar/PfamIE/main/docs/screenshots/field-guide.png" alt="The Field Guide answering a plain-English query offline"></td>
</tr>
<tr>
<td><b>Galaxy.</b> Every family, coloured by clan, the dark proteome drawn dim.</td>
<td><b>Oracle.</b> Human SRC: the kinase domain at 91%, read from residues 281 to 536 (InterPro says 271 to 518).</td>
<td><b>Field Guide.</b> "breaks down plastic" finds PETase, with no network.</td>
</tr>
<tr>
<td><img src="https://raw.githubusercontent.com/bellcheddar/PfamIE/main/docs/screenshots/grammarian.png" alt="The Grammarian showing SH2 co-occurrence"></td>
<td><img src="https://raw.githubusercontent.com/bellcheddar/PfamIE/main/docs/screenshots/prospector.png" alt="The Prospector listing unknown-function families"></td>
<td><img src="https://raw.githubusercontent.com/bellcheddar/PfamIE/main/docs/screenshots/vision-window.png" alt="PfamIE running on Apple Vision Pro"></td>
</tr>
<tr>
<td><b>Grammarian.</b> SH2 and the domains it travels with, across 1,896 architectures.</td>
<td><b>Prospector.</b> 6,925 families with no assigned function, largest first.</td>
<td><b>visionOS.</b> The same five views as a window in the room.</td>
</tr>
</table>

## 🥽 The Pfam universe in a volume

<img src="https://raw.githubusercontent.com/bellcheddar/PfamIE/main/docs/screenshots/vision-volume.png" alt="30,031 Pfam families rendered as a volumetric point cloud in a living room" width="100%">

On visionOS the Galaxy leaves the window. All 30,031 families render as a **RealityKit volume** you can walk around and lean into, clans holding their colour, the dark proteome dim, with the family card following as an ornament below.

Two things make that work at all:

- **Batched geometry.** RealityKit has no point primitive, and the obvious implementation (one `ModelEntity` per family) is 30,031 entities and 30,031 draw calls, which never reaches frame rate. Families are batched into **one generated mesh per clan**, so a scene of 30,031 objects becomes at most 892 draws.
- **Tetrahedra, not billboards.** A flat quad has to be reoriented every frame in a volume the viewer walks around, and vanishes edge-on when it is not. A four-triangle tetrahedron per family is cheaper than the reorientation and correct from every angle.

The other four views open as ordinary windows reusing the shared SwiftUI code untouched. There is no visionOS fork of the app: one `RootView` adapts by size class across iPhone, iPad, Mac and Vision Pro.

## ⚡ On the Neural Engine

The whole point of the app is that a transformer runs locally, fast enough that classification feels like a lookup. Measured on an M1 Max:

Reproduce with `./Tools/benchmark.sh`. They are excluded from the normal test
run on purpose: see the note below the table.

| Operation | Time | Notes |
|---|---|---|
| ESM-2 t12-35M embedding, 512 tokens, **Neural Engine** | **31.3 ms** | |
| the same on CPU | 76.1 ms | **2.4x slower** |
| Top-20 search over 30,031 families | **1.8 ms** | Accelerate `sgemv` over a memory-mapped int8 matrix |
| Field Guide query over 30,031 descriptions | **8.6 ms** | MiniLM embed plus a second `sgemv` |
| **Full classification of a 536-residue protein** | **~1.2 s** | 33 windows across four scales, end to end |

The smaller t6-8M tier runs at 6.0 ms per window and classifies the same
protein in 247 ms, four times faster. It was the shipped model until the
measurements below said otherwise.

**Benchmarks only mean something run alone**, which took two goes to get right.
Left in the normal test run, the other suites drive Core ML concurrently, the
Neural Engine queue saturates, and a 31 ms embedding measures at 494 ms while
the CPU path stays flat: the benchmark concluded the ANE was five times
*slower*. Interleaving the two paths to equalise the load made it worse again,
because alternating between an ANE-resident model and a CPU one reloads the
Neural Engine context every call. Consecutive blocks, in an opt-in suite that
runs on its own, is the only arrangement that measures the model.

### How the models are shaped for the ANE

- **Fixed input length.** ESM-2 is converted at exactly 512 tokens and MiniLM at 256. Flexible shapes make the Neural Engine ineligible and, on Metal, force a graph recompilation per distinct shape.
- **8-bit palettisation** for both models. It halves ESM-2 t12 from 69 MB to 34 MB and MiniLM from 45 MB to 23 MB, and costs nothing measurable: identical Neural Engine latency, and end-to-end top-1 unchanged at 0.78 on held-out sequences through the converted model.
- **The whole recipe is compiled into the graph.** Masked mean pooling, the whitening transform and L2 normalisation are all graph operations, so the model takes tokens and returns a finished unit vector. Two benefits: Swift never has to index a multi-dimensional `MLMultiArray` (Core ML pads rows, and indexing by `index * width` instead of `strides` silently shifts every value after the first), and the on-device vector is bit-comparable with the one the forge computed.

### The float16 trap that ships silently

Baking the whitening into the graph made the **Neural Engine return all zeros while the CPU path looked perfect**. The whitening matrix has entries up to 200, so the whitened vector's norm runs into the hundreds and its sum of squares exceeds float16's 65,504. The ANE computes in float16, so the norm overflowed to infinity and the normalisation divided by it.

The output is L2 normalised, so scaling the whitening matrix is mathematically free. The forge now scales it so a typical sequence lands near unit length, **and asserts parity on `ComputeUnit.ALL` as well as CPU**, failing the build rather than shipping a model that returns zeros on device. A check that has only ever run on the CPU is not a check.

## 🔬 The science

### Classification without an HMM

Pfam assignment is conventionally a profile HMM search. PfamIE does something different: it embeds the query with a protein language model and finds the nearest **family centroid** in that embedding space. The centroids are built once, in the forge, from Pfam's own seed alignments.

Two findings shaped the result, and both are the kind that only appear when you measure.

**1. Mean-pooled ESM-2 embeddings are strongly anisotropic.** Raw, every family sits at cosine ~0.97 to every other, and short families collapse into a single hub. The geometry is nearly meaningless. Whitening the centroid covariance fixes it:

| | top-1 | top-5 | mean nearest-neighbour cosine |
|---|---|---|---|
| Raw mean-pooled | 0.514 | 0.641 | 0.968 |
| **Whitened** | **0.715** | **0.810** | **0.677** |

A shrinkage sweep put the plateau at `eps = 1e-5`, which also caps eigenvalue amplification at a conservative 34x. Without whitening the Galaxy is a featureless ball and the Oracle is close to a coin toss.

**2. How you choose the centroid's sequences matters more than how many.** Picking the seed sequences closest to the median length looks sensible and does the opposite: it selects near-duplicates. PF00062 (Lys) covers both c-type lysozymes and the alpha-lactalbumins, and typicality chose **six lactalbumins out of eight**, leaving a centroid that could not recognise hen lysozyme (rank 42 of 30,031). Seed alignments are ordered roughly phylogenetically, so an even sweep through them costs nothing and spans the family. Hen lysozyme moved to **rank 2**.

### A real protein is not a trimmed domain

The single most important measurement in this project is the gap between two benchmarks:

| Benchmark | top-1 | What it measures |
|---|---|---|
| Held-out Pfam seed sequences | 0.75 | The index against its own kind |
| **Real UniProt proteins** | **0.49** | **What the app is actually handed** |

Seed sequences are trimmed to domain boundaries and drawn from the alignments the centroids were built from. Real proteins carry signal peptides, linkers, disordered tails and other domains, and embedding one end to end averages all of that into the answer. Quoting the seed number would have been comfortable and wrong, and every figure in this README is the real-protein one.

Acting on it changed the engine. Scanning at several window widths, measured on 400 real single-domain proteins:

| Approach | top-1 | top-5 |
|---|---|---|
| Whole sequence embedded end to end | 0.285 | 0.435 |
| One 160-residue sliding window | 0.425 | 0.548 |
| **Four widths: 96 / 160 / 256 / 384** | **0.535** | **0.635** |

No single width fits Pfam, whose domains run from about 30 residues to several hundred. The headline answer now comes from the **best-reading window** and says which residues it read, which is both more accurate and a more useful thing to tell a user than a whole-sequence guess.

### Confidence you can act on

A ranking without a calibrated confidence is an invitation to over-trust it. The softmax temperature and the band thresholds are fitted on **2,500 real UniProt proteins**, with thresholds chosen on 1,875 and every figure below measured on the 625 held back:

| Band | Share of queries | Correct |
|---|---|---|
| **High** (p ≥ 0.85) | 19.7% | **93.5%** |
| **Moderate** (p ≥ 0.45) | 31.2% | 69.7% |
| **Low** (p ≥ 0.20) | 30.6% | 23.6% |
| **No confident family** (p < 0.20) | 18.6% | 5.2% |

Every result carries the measured accuracy of its own band, and the bottom band exists so the app can say "no confident family" instead of naming the least-bad of 30,031 options. **A test fails the build if the shipped calibration ever matches the seed-fitted one**, because that would overstate accuracy by about 25 points.

### Domain grammar is real and strongly conserved

Across 71,573 domain pairs sharing at least ten proteins, **97.7% have an invariant N-to-C order**. SH3 is always N-terminal to SH2; the tyrosine kinase domain is always C-terminal to it. The Grammarian says so in words for the invariant majority and keeps a percentage for the 2.3% that genuinely vary, because those are the interesting ones.

### Honest limits

- ESM-2 t12-35M is **33.5 million parameters**. 0.49 top-1 on real proteins against 30,031 classes is respectable for that size and is not an HMM replacement. The next tier up (t30-150M) is untested here.
- Domain **detection** is the binding limit, not localisation: in a multi-domain protein the scanner finds 47.8% of the true domains, at 0.84 precision. Boundaries for the domains it does find are median 61 residues out.
- Nearest-neighbour proximity in the Prospector is **a reason to look, not evidence of function**, and the wording throughout that tab says so.
- There is no hub pathology: the most-connected family is the nearest neighbour of only 19 of 30,031, and the top 15 absorb 0.6% of nearest-neighbour slots.

## ✨ The five views

| Tab | What it is for |
|---|---|
| **Galaxy** | All 30,031 families as a 3D point cloud, clans as coloured regions, the dark proteome drawn dim. Tap a star, open its card, or watch your last query drop in as an amber comet. |
| **Oracle** | Paste a sequence or open a FASTA. Multi-scale scanning returns the family, the clan, the N-to-C architecture and a calibrated confidence. |
| **Grammarian** | Which domains travel with which, in what order, and how often: co-occurrence over 151,818 real architectures, and "what else is built like mine?" |
| **Prospector** | The 6,925 families with no known function, each with its nearest annotated neighbours as an explicitly hypothesis-flavoured lead. |
| **Field Guide** | The offline Pfam atlas. Plain-English queries work with no network, through a bundled MiniLM, alongside FTS5 for names and accessions. |

Every family reference anywhere carries the same four actions (**Open card · Show in Galaxy · Similar architectures · View structure**), so no tab is a dead end. Any family opens an AlphaFold model with its Pfam domain highlighted: AlphaFold uses UniProt numbering, so Pfam boundaries map onto the structure with no residue-mapping step.

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

| Component | Notes |
|---|---|
| `ProteinEmbedder` | ESM-2 t12-35M as Core ML, 8-bit palettised, fixed 512 tokens, Neural Engine eligible, returns a finished unit vector. |
| `Int8Matrix` | Memory-mapped int8 with a per-row scale and a chunked Accelerate `sgemv`. The scale is applied to the result, not to every element. |
| `DomainScanner` | Multi-scale windows, per-scale merging, then greedy non-overlapping selection by confidence. |
| `SemanticSearch` | MiniLM as Core ML plus a Swift WordPiece tokeniser over 30,031 description embeddings. |
| `PfamStore` | Raw sqlite3, no wrapper library. FTS5 alongside the semantic search, not instead of it. |
| `Router` | One closed `Destination` enum. Every context menu and card action resolves to a case of it. |

All five platforms share one engine. `PfamIEKit` imports no UIKit or AppKit except the two files behind the structure viewer, which need a web view and say so. The watch carries no assets and no model: the phone classifies and sends a summary.

## ⚗️ The forge

`forge/` builds everything the app ships, from the Pfam 38.2 release flatfiles and the InterPro API. Reading the flatfiles rather than the API replaces 30,031 requests with one 52 MB download.

```bash
python3.12 -m venv .venv
.venv/bin/pip install -r forge/requirements.txt

mkdir -p assets/raw && cd assets/raw
for f in Pfam-A.clans.tsv.gz Pfam-C.gz Pfam-A.hmm.dat.gz Pfam-A.seed.gz; do
  curl -sLO "https://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/$f"
done
cd ../..

.venv/bin/python forge/stage_metadata.py        # families, clans, representative sequences
.venv/bin/python forge/stage_interpro.py ida    # domain architectures (about 100 min, resumable)
.venv/bin/python forge/stage_interpro.py counters
.venv/bin/python forge/stage_embed.py           # ESM-2 over 368,451 sequences
.venv/bin/python forge/stage_transform.py       # whitening and the seed reference calibration
.venv/bin/python forge/stage_project.py         # 3D UMAP for the Galaxy
.venv/bin/python forge/stage_descemb.py         # MiniLM over every abstract
.venv/bin/python forge/stage_coreml.py          # Core ML conversion and parity checks
.venv/bin/python forge/stage_calibrate_real.py  # confidence, fitted on real proteins
.venv/bin/python forge/stage_sqlite.py
.venv/bin/python forge/stage_emit.py
.venv/bin/python forge/make_icon.py             # the app icon, drawn from the real map
```

| Stage | Produces |
|---|---|
| `stage_metadata` | 30,031 families, 891 clans, 6,925 unknown-function, a UniProt structural representative for every family |
| `stage_interpro` | 151,818 distinct N-to-C architectures and 151,719 co-occurrence edges |
| `stage_embed` | 403,367 ESM-2 embeddings, 16 stratified seed sequences per centroid |
| `stage_transform` | The 480 x 480 whitening transform |
| `stage_coreml` | Two `.mlpackage` models, parity asserted on the Neural Engine and end to end against the index |
| `stage_calibrate_real` | The shipped temperature and confidence bands |
| `stage_emit` | `centroids.bin`, `umap3d.bin`, `desc_emb.bin`, `manifest.json` |

## 🔧 Building the app

```bash
brew install xcodegen
./Tools/generate-project.sh                 # regenerates PfamIE.xcodeproj from project.yml
open PfamIE.xcodeproj

xcodebuild -project PfamIE.xcodeproj -scheme PfamIE-macOS -destination 'platform=macOS' build
swift test -c release --package-path PfamIEKit
```

Tests need the forge output. Without it the asset-dependent suites skip rather than fail, so a fresh clone still runs green.

**Always verify a built bundle.** `BUILD SUCCEEDED` says nothing about the contents, and an app missing its Core ML models builds and signs perfectly:

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
| Bundle | About 148 MB: 58 MB database, 26 MB matrices (int8), 57 MB models, 5 MB Mol\* |
| Network | Only for AlphaFold structures, and for InterProScan verification if you opt in. Classification, architecture and search are entirely offline. |

## ✅ To Do

Roadmap for PfamIE, in dependency order. Suggestions welcome.

- [x] **Phase 0: the data forge.** Reads the Pfam 38.2 flatfiles offline rather than making 30,031 API calls. Only architectures and family sizes need InterPro.
- [x] **Whitening the centroid space.** Measured, not assumed: held-out top-1 0.514 to 0.715, nearest-neighbour cosine 0.968 to 0.677. Shrinkage sweep found the plateau at eps 1e-5, which caps eigen-amplification at 34x.
- [x] **Stratified centroid sequences.** Choosing by closeness to median length selects near-duplicates: PF00062 got six alpha-lactalbumins out of eight and could not recognise hen lysozyme. An even sweep across the alignment moved it from rank 42 to rank 2.
- [x] **Core ML conversion with parity asserted on the Neural Engine.** The whitened vector's sum of squares overflows float16 in the norm reduction, so the ANE returned all zeros while the CPU looked perfect. Scaling `W` is free because the output is L2 normalised.
- [x] **Phase 1: engine.** Memory-mapped float16 matrices, chunked Accelerate gemv at 1.8 ms per query, raw sqlite3 store, Swift ESM-2 and WordPiece tokenisers.
- [x] **Multi-scale domain scanning.** Whole-sequence embedding is the *weakest* signal on real proteins (0.285 top-1). Four window widths give 0.535 at no bundle cost.
- [x] **Confidence calibrated on real proteins.** Not on held-out seed sequences, which overstate accuracy by about 30 points. A test fails the build if the shipped calibration ever matches the seed-fitted one.
- [x] **Phases 2 and 3: five tabs.** Plus the universal family card and the closed-enum router.
- [x] **Structure layer.** Bundled Mol\*, AlphaFold mmCIF with disk caching, domain highlighting in UniProt numbering, and a quiet offline note rather than a spinner that never resolves.
- [x] **Tightened the unknown-function rule.** Matching the CC abstract as well as the summary flagged 949 characterised families: the Prospector's largest entries were the MurJ lipid II flippase and the ZIP zinc transporter. Matching the family's own summary plus Pfam's DUF and UPF prefixes gives 6,925.
- [x] **Said conserved domain order in words.** Every co-occurrence row read "100%", which looks like a bug and is not one: 97.7% of pairs have an invariant N-to-C order.
- [x] **All five platforms building.** visionOS needed the volumetric Galaxy rebuilt as batched meshes (30,031 entities would never reach frame rate) and a route to the volume, which a volumetric `WindowGroup` does not open on its own.
- [x] **Trimmed the database.** 83 MB to 58 MB. The `signature` column and its unique index cost 16 MB to repeat what `architecture_member` already held.
- [x] **Bundle verification, negative-tested.** Checks every model, matrix, database and the compiled icon at the bundle root.
- [x] **App icon, drawn from the real map.** Asserts RGB with no alpha, because the App Store rejects an alpha channel and PIL hands you RGBA by default.
- [x] **Trimmed the matrices to int8.** Free: top-1 0.7150 against 0.7149 at float16, an identical top hit for every description probe, worst round-trip cosine 0.99990. Centroids 18 MB to 9.7 MB, descriptions 23 MB to 11.7 MB, bundle 146 MB to 125 MB. The scale is applied to the result rather than to every element, since the product of a row and the query is linear in the row.
- [x] **Adopted ESM-2 t12-35M.** Measured first, then chosen. The top-1 gain is real but the multi-domain numbers are what decided it: the architecture track is what the Grammarian consumes, and it finds a third more domains at higher precision. Hen lysozyme went from a wrong call at 79% confidence to **Lys at 97%**, with Destabilase and Glyco_hydro_19 behind it. The cost is accepted deliberately: the Oracle no longer feels instant.

  | | t6-8M | **t12-35M (shipped)** |
  |---|---|---|
  | Real-protein top-1 | 0.430 | **0.492** |
  | Real-protein top-5 | 0.493 | **0.553** |
  | Multi-domain recall | 0.358 | **0.478** |
  | Multi-domain precision | 0.76 | **0.84** |
  | Neural Engine, per window | 6.0 ms | 31.3 ms |
  | Model in the bundle (8-bit) | 16.5 MB | 34.4 MB |
  | 536-residue protein, end to end | 247 ms | ~1.2 s |

- [x] **Boundary refinement: tried, measured, rejected.** Worth recording so nobody tries it again blind. The premise needed correcting twice. On single-domain proteins boundaries are already good (median error 6 and 7 residues, IoU 0.87), but that population flatters the scanner, because in a protein that is one domain end to end almost any call scores well. On multi-domain proteins, where boundaries actually matter, median error is 48 and 54 residues and IoU is 0.44.

  Two fixes were measured against InterPro's own Pfam locations for 220 multi-domain proteins. A second pass of narrow 48-residue tiles scored against the family already called made it clearly **worse** (IoU 0.44 to 0.19): tiles that narrow do not carry enough signal to match a centroid built from ~120-residue domains. Per-residue vote segmentation lifted recall (0.358 to 0.471) but nearly halved precision (0.76 to 0.41) by over-calling. Neither shipped.

  The real limit is detection, not localisation: the scanner never finds two thirds of the domains, and that is a model-capacity problem. t12-35M lifts recall to 0.478 at *higher* precision, which is where the gain actually is.
- [x] **visionOS immersive space.** The volume is a box you lean into; the immersive space puts the map around you at room scale and lets you walk through it. Mixed immersion rather than full, because this is an instrument and seeing the desk is part of using one. Same batched per-clan meshes.
- [ ] **Hand-tracked comet placement.** Deferred deliberately rather than left unsaid: it needs ARKit hand tracking, which cannot be exercised in the simulator, so it would ship untested. Worth doing on real hardware.
- [x] **Camera sequence scanning.** VisionKit live text, but the OCR is the easy half: the work is deciding which recognised text is a sequence, and that is tested without a camera. Whitespace is skipped rather than separating (printed sequences come in blocks of ten), runs are built from the twenty standard residues only (O and U are among the commonest letters in English and are not amino acids, so "PROTEIN" breaks at the O), and a run must sit under an English-bigram density of 0.17. Measured: 300 real Pfam seed sequences peak at 0.148, capitalised prose starts at 0.200.
- [x] **Online verification against InterProScan 5.** EBI's hmmscan POST endpoint is gone (405) and the maintained route is InterProScan, which is also the authoritative answer PfamIE approximates rather than merely a second opinion. Result parsing filters to Pfam signatures, since a Gene3D superfamily would read as a disagreement that is not one, and is tested against a captured response rather than by queueing jobs on shared public infrastructure. The email is the user's own: it is their sequence and their job. This is the only feature that leaves the device, so it asks first and says what it will send.
- [x] **watchOS complication.** Circular, corner, inline and rectangular, showing the last family the phone classified. It reads an App Group rather than `UserDefaults.standard`, because a widget extension has its own container and the standard store would be a different, always-empty one: the classic way a complication ships stuck on its placeholder.
- [x] **TestFlight tooling, tested rather than written.** Bundle IDs, capabilities and five provisioning profiles are created and installed over the App Store Connect API; `archive.sh`, `verify-archive.sh` and `upload.sh` do the rest. A real macOS release archive has been produced, signed with `Apple Distribution: Marc Deller (SYNV8TWB5Z)` and verified complete. Writing the scripts was the easy half: running them surfaced that Release was silently picking the *Development* certificate, and that **Apple reserves "complication" in the App ID namespace**, rejecting it at any depth while `.widget` under the same parent is fine. See [docs/TESTFLIGHT.md](https://github.com/bellcheddar/PfamIE/blob/main/docs/TESTFLIGHT.md).
- [ ] **Two one-off portal steps, then upload.** Both need a human and are documented with the exact thing to click. The **App Store Connect app record**: Apple returns 403 on `POST /v1/apps`, and the store name is globally unique so it may be taken. The **App Group** `group.com.mdeller.pfamie`: the `APP_GROUPS` capability is already enabled over the API, but App Store Connect has no `/appGroups` resource, so the group itself is created in the Developer Portal. Only the watch complication needs it; the macOS archive works today.

## 🔬 Data sources and licences

PfamIE is **MIT licensed**. Every bundled component is MIT, Apache-2.0 or CC0, so nothing here carries a copyleft or non-commercial term. Full attribution is in [THIRD-PARTY-NOTICES.md](https://github.com/bellcheddar/PfamIE/blob/main/THIRD-PARTY-NOTICES.md).

| Source | Licence | Used for |
|---|---|---|
| [Pfam 38.2](https://ftp.ebi.ac.uk/pub/databases/Pfam/current_release/) | CC0 1.0 | Family metadata, clans, abstracts, seed alignments |
| [InterPro](https://www.ebi.ac.uk/interpro/) | EMBL-EBI, freely available | Domain architectures, family sizes, taxonomic breadth |
| [ESM-2](https://huggingface.co/facebook/esm2_t6_8M_UR50D) | MIT | Protein sequence embeddings |
| [all-MiniLM-L6-v2](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) | Apache-2.0 | Description embeddings for offline semantic search |
| [Mol\*](https://molstar.org/) | MIT | Structure rendering |
| [AlphaFold DB](https://alphafold.ebi.ac.uk/) | CC-BY 4.0 | Predicted structures, fetched on demand, never redistributed |
| [UniProt](https://www.uniprot.org/) | CC-BY 4.0 | Benchmark and calibration sequences (forge only) |

If PfamIE contributes to published work, please cite the underlying resources rather than this app. The citations are listed in [THIRD-PARTY-NOTICES.md](https://github.com/bellcheddar/PfamIE/blob/main/THIRD-PARTY-NOTICES.md#how-to-cite-the-science).

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
