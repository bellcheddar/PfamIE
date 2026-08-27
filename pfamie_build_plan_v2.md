# PfamIE: Protein Family Inference Engine
## Claude Code Build Plan v2 (one-day build, 4 phases, five platforms)

**Author:** Marc C. Deller, D.Phil. (marcdeller.com)
**Platforms:** Swift / SwiftUI multiplatform: iPhone + iPad (iOS 18+), macOS 15+ (native, not
Catalyst), visionOS 2+, watchOS 11+ companion. Apple Neural Engine via Core ML on every
target that has one.
**Repo:** `github.com/bellcheddar/PfamIE`
**Timebox:** 1 day for Tier 1 (iPhone, iPad, Mac: roughly 2 h + 3 h + 2.5 h + 2.5 h), with
visionOS and watchOS scaffolded on day one and polished in a half-day follow-up. Building
one shared core from minute one is what makes five platforms honest rather than heroic.
**Language conventions:** British English throughout the UI and docs. No em dashes (use colons or parentheses).

---

## 1. Concept

PfamIE turns the entire Pfam universe into an on-device inference engine. A quantised ESM-2
protein language model runs on the Apple Neural Engine, embeds any input sequence, and
classifies it against a pre-baked matrix of Pfam family centroid embeddings: instant, offline,
HMM-free family assignment. Around that core sit five integrated views:

| Tab | Codename | One-liner |
|-----|----------|-----------|
| 1 (landing) | **Galaxy** | 3D flythrough map of all ~21k Pfam families, clans as coloured galaxies; query sequences drop in as live comets |
| 2 | **Oracle** | Paste/share/scan a sequence, get family + clan + parsed domain architecture with calibrated confidence |
| 3 | **Grammarian** | Domain architecture explorer: co-occurrence networks, N-to-C grammar, "what proteins are built like mine?" |
| 4 | **Prospector** | DUF (domain of unknown function) browser with nearest-annotated-neighbour functional hypotheses |
| 5 | **Field Guide** | Offline Pfam atlas with natural-language semantic search over family descriptions |

**Structure layer (cross-cutting):** every family, everywhere in the app, can open an embedded
structural viewer showing a representative AlphaFold model with the Pfam domain highlighted.
AlphaFold models use UniProt numbering, so Pfam domain boundaries map directly with no
SIFTS gymnastics.

### Differentiation guardrails (do not drift into sibling apps)

- **Not CODSWALLOP:** no PDB mining, no crystallisation conditions, no per-family structure
  tables. CODSWALLOP clusters structures *within* a family; the Galaxy clusters all families
  *against each other*. Structures here are single AlphaFold representatives used as visual
  anchors only.
- **Not BOFFIN:** no variant effect scanning, no construct design. BOFFIN's homolog search is
  sequence-vs-sequence; PfamIE's Oracle is sequence-vs-family-centroid classification.
- **Not JUMPjet:** no dynamics, no trajectories, and a deliberately different visual identity
  (see Deep Field below; JUMPjet owns the "Night Sortie" military HUD).

---

## 2. Platform matrix

| Platform | Tier | Role | Key adaptations |
|----------|------|------|-----------------|
| iPhone | 1 | Reference experience | Five-tab `TabView`, everything in the phases below |
| iPad | 1 | Workbench | Same target as iPhone; `NavigationSplitView` three-column (tabs → list → detail), pointer hover on Galaxy points, keyboard shortcuts (⌘F search, ⌘1-5 tabs) |
| macOS | 1 | Desk instrument | Native SwiftUI destination (NOT Catalyst); sidebar navigation, resizable Galaxy window, menu bar commands, drag-a-FASTA-onto-the-dock-icon to classify; the Data Forge also runs here |
| visionOS | 2 | The showpiece | The Galaxy as a **volumetric RealityKit scene**: the Pfam universe rendered in a volume you physically walk around, gaze + pinch to select families; Oracle/Grammarian/Prospector/Field Guide as ornament-adorned windows; M-series chip means full ANE inference |
| watchOS | 2 | Companion glance | No on-watch transformer: phone computes, `WatchConnectivity` syncs. Shows last classification (family, clan, confidence ring as a circular gauge), a "family of the day" complication, and a static constellation snapshot of your recent queries. S9+ Neural Engine reserved as a stretch for on-watch k-NN only |

**Shared-core rule (non-negotiable):** all engine, data, and model code lives in a SwiftPM
package (`PfamIEKit`) with zero UIKit/AppKit imports. Platform targets are thin view layers.
Renderer and viewer availability differs by platform, so two seams are abstracted from the
start:

- `GalaxyRenderer` protocol → SceneKit implementation (iOS/iPadOS/macOS), RealityKit
  volumetric implementation (visionOS), static Canvas snapshot (watchOS).
- `StructureViewing` → Mol* WKWebView (iOS/iPadOS/macOS/visionOS; WKWebView exists on all
  four), cached snapshot image only (watchOS, no WKWebView there).

---

## 3. Design language: "Deep Field"

Named after the Hubble Deep Field. The app should feel like an astronomy instrument pointed
at sequence space. Follow Apple HIG throughout: native components first, custom chrome only
where it earns its keep.

### Colour tokens (Assets.xcassets, both appearances)

| Token | Dark (default) | Light |
|-------|----------------|-------|
| `bgDeep` | `#070B14` (near-black indigo) | `#F5F7FB` |
| `bgRaised` | `#0E1524` | `#FFFFFF` |
| `inkPrimary` | `#E8EDF7` | `#101828` |
| `inkSecondary` | `#8A96AD` | `#5B6779` |
| `accentNova` | `#5EEAD4` (bioluminescent teal, primary accent) | `#0D9488` |
| `accentPulsar` | `#A78BFA` (violet, secondary/clan accent) | `#7C3AED` |
| `accentFlare` | `#FBBF24` (amber, query comet + warnings) | `#D97706` |
| `confidenceHigh/Mid/Low` | teal / amber / rose ramp | same hues, darkened |

- **Dark theme is the default.** Light mode fully supported. Switcher: System / Dark / Light
  segmented control in Settings, persisted with `@AppStorage("appearance")`, applied via
  `.preferredColorScheme`. Respect the system setting when "System" is selected.
- Materials: `.ultraThinMaterial` bars over the Galaxy, `.regularMaterial` cards elsewhere.
  Depth from blur and glow, not drop shadows.
- Typography: SF Pro (text), SF Pro Rounded for large numerics (confidence %, counts),
  SF Mono for sequences and architecture strings. Dynamic Type respected everywhere.
- SF Symbols per tab: `sparkles` (Galaxy), `wand.and.stars` (Oracle), `puzzlepiece.extension`
  (Grammarian), `questionmark.diamond` (Prospector), `books.vertical` (Field Guide).
- Haptics: `.sensoryFeedback(.success)` on classification complete, `.selection` on Galaxy
  point lock-on, `.impact(.soft)` on card expansion.
- Motion: numeric transitions with `.contentTransition(.numericText())`, matched geometry on
  family cards, and a subtle parallax starfield behind list views (respect Reduce Motion).

---

## 4. Architecture

```
PfamIE/
├── PfamIEKit/          (SwiftPM package: everything below, no UIKit/AppKit imports)
├── Apps/
│   ├── iOS/            PfamIEApp.swift (iPhone TabView + iPad NavigationSplitView)
│   ├── macOS/          sidebar app, menu commands, FASTA drag-and-drop
│   ├── visionOS/       volumetric Galaxy + windowed tabs
│   └── watchOS/        companion: WatchConnectivity sync, complication, glance views
├── App/                AppState.swift, Router.swift, Theme.swift (shared via PfamIEKit)
├── Engine/
│   ├── ESM2Embedder.swift        (Core ML wrapper, ANE compute units)
│   ├── Tokenizer.swift           (ESM-2 vocab, Swift-native)
│   ├── CentroidIndex.swift       (mmap'd Float16 matrix + cosine k-NN, Accelerate/vDSP)
│   ├── DomainScanner.swift       (sliding-window architecture parser)
│   └── SemanticSearch.swift      (description embedding search, Field Guide)
├── Data/
│   ├── PfamStore.swift           (SQLite via GRDB or raw sqlite3: family metadata)
│   ├── InterProClient.swift      (async REST client, cached)
│   └── AlphaFoldClient.swift     (representative model fetch + disk cache)
├── Views/
│   ├── Galaxy/                   (SceneKit/Metal point cloud + overlays)
│   ├── Oracle/                   (input, results, architecture track)
│   ├── Grammarian/               (architecture cards, co-occurrence graph)
│   ├── Prospector/               (DUF list, neighbour hypotheses)
│   ├── FieldGuide/               (search, atlas, family cards)
│   └── Shared/                   (FamilyCard, StructurePeek, ConfidenceRing, Starfield)
├── Structure/
│   └── MolViewer.swift           (WKWebView + bundled Mol*, domain-range highlighting)
└── Resources/
    ├── ESM2_t6_8M.mlpackage      (quantised, ~7 MB)
    ├── centroids.bin             (21k x 320 Float16, ~13 MB)
    ├── umap3d.bin                (21k x 3 Float32 coordinates)
    ├── pfam.sqlite               (metadata: id, name, clan, description, type, DUF flag,
    │                              representative UniProt acc, top architectures, taxonomy depth)
    └── molstar/                  (single-file Mol* build, offline)
```

**Cross-reference router (the connective tissue Marc asked for):**

```swift
enum Destination: Hashable {
    case family(PfamID)              // universal family card (sheet)
    case galaxy(focus: PfamID?)      // fly camera to a family's point
    case oracle(prefill: String?)    // classify this sequence
    case grammarian(architecture: [PfamID])
    case prospector(duf: PfamID)
    case structure(uniprot: String, highlight: ClosedRange<Int>?)
}
```

Every family chip, everywhere, offers the same context menu: **Open card · Show in Galaxy ·
Similar architectures · View structure**. The card itself carries "Scan a sequence against
this family" (deep-links to Oracle). One `Router` object in the environment; no tab is a
dead end.

---

## 5. Phase 0 (pre-Xcode): The Data Forge

A Python script Claude Code writes and runs FIRST on the Mac (`forge/build_assets.py`).
Everything downstream depends on these baked assets.

1. **Pull family metadata** from the InterPro REST API (Pfam is served here; the standalone
   Pfam site/API is retired):
   `https://www.ebi.ac.uk/interpro/api/entry/pfam/?page_size=200` (paginate all ~21k entries).
   Capture: accession, name, short name, clan/set, entry type, description (abstract),
   representative/seed info. Flag DUFs (`name starts with "DUF"` or description heuristic).
2. **Representative sequences:** for each family take a representative UniProt accession
   (InterPro `representative` or first reviewed match via
   `https://www.ebi.ac.uk/interpro/api/protein/reviewed/entry/pfam/{acc}/?page_size=1`),
   store accession + matched domain range for the structure layer.
3. **Embed:** run ESM-2 t6-8M (Hugging Face `facebook/esm2_t6_8M_UR50D`) over one to three
   representative domain sequences per family; mean-pool per-residue embeddings over the
   domain range; average into a 320-dim Float16 centroid. (t6-8M keeps the forge under an
   hour on Apple Silicon; t12-35M is a stretch goal, not for today.)
4. **Project:** 3D UMAP (n_neighbors=25, min_dist=0.08, cosine) of the centroid matrix for
   Galaxy coordinates. Save clan colour assignments (stable hash of clan acc into the
   pulsar-violet/teal hue wheel).
5. **Description embeddings** for Field Guide semantic search: MiniLM-L6-v2 (384-dim) over
   each family abstract, Float16.
6. **Convert ESM-2 to Core ML:** `coremltools` with fixed input length 512, Float16 weights,
   `compute_units=.all` so the ANE is eligible; verify with a known sequence that Swift-side
   and Python-side embeddings agree (cosine > 0.999).
7. **Emit:** `centroids.bin`, `umap3d.bin`, `desc_embeddings.bin`, `pfam.sqlite`,
   `ESM2_t6_8M.mlpackage`. Print total bundle weight (target: under 60 MB).

**Acceptance:** forge runs end to end; spot-check that PF00069 (Pkinase) lands near PF07714
(PK_Tyr_Ser-Thr) in both centroid space and UMAP space.

---

## 6. Phase 1 (~2 h): Scaffold, theme, engine bring-up

- Xcode workspace with `PfamIEKit` (SwiftPM) plus all four app targets compiling from the
  first commit: iOS/iPadOS, macOS, visionOS, watchOS. Tier 2 targets can be near-empty
  shells today, but they build; retrofitting platforms later is how multiplatform dies.
- iPhone: five-tab `TabView` with SF Symbols. iPad: `NavigationSplitView` variant of the
  same target. macOS: sidebar navigation. Deep Field colour assets (both appearances),
  appearance switcher working end to end on all Tier 1 platforms.
- `Theme.swift` with all tokens; Starfield background component (Canvas, Reduce Motion aware).
- Bundle the forge assets. `PfamStore` (SQLite) loading and queryable; `CentroidIndex`
  mmap + vDSP cosine k-NN returning top-20 in under 5 ms on device.
- `ESM2Embedder` + `Tokenizer`: load the mlpackage, embed a test sequence, confirm ANE
  execution in Instruments (Core ML report shows Neural Engine dispatch).
- Shared `FamilyCard` sheet skeleton (name, clan chip, description, placeholder structure
  peek) and the `Router` with all `Destination` cases stubbed.

**Acceptance:** app launches to an empty Galaxy tab in dark mode, switcher toggles all three
modes, a hard-coded lysozyme sequence prints its top-5 families to the console with sensible
ranking (PF00062 near the top).

---

## 7. Phase 2 (~3 h): Galaxy landing + Oracle

**Galaxy (landing page, the showpiece):**
- SceneKit point cloud from `umap3d.bin`: one `SCNGeometry` with per-vertex colour (clan
  hue) and size (log family size), additive blending for glow, slow idle drift rotation.
- Pinch/drag/rotate camera; tap performs hit-test, locks on, shows a floating
  `.ultraThinMaterial` chip (family name, clan) with "Open card" and haptic `.selection`.
- Clan legend drawer; search field that flies the camera to a named family
  (`Destination.galaxy(focus:)` implemented).
- **Query comet:** when Oracle classifies a sequence, its embedding is projected into the
  map (nearest-centroid barycentric placement among top-5 neighbours is fine for v1; exact
  UMAP transform is a stretch goal) and rendered as an amber `accentFlare` comet with a
  short particle trail. Tapping the comet reopens the Oracle result.
- Fallback if SceneKit fights the timebox: 2D Canvas starfield with the same interactions
  (decide by the phase midpoint, do not sink the day here).

**Oracle:**
- Input: paste, Files/share-sheet import (FASTA), or VisionKit live-text scan of a printed
  sequence (nice conference party trick, 20 min budget, cut first if tight).
- Full-sequence embed + top-k families with `ConfidenceRing` (softmax over cosine similarities
  with temperature calibrated in the forge; label High/Mid/Low honestly, and say "no confident
  family" below threshold rather than bluffing: DUF-adjacent inputs will happen).
- `DomainScanner`: sliding window (width 160, stride 40) classification, merge contiguous
  same-family windows into domain calls, render an interactive architecture track
  (SF Mono ruler, coloured domain lozenges, tap a lozenge for the family card).
- Result actions: Show in Galaxy · Verify online with HMMER (optional POST to EBI hmmscan,
  clearly labelled as the network path) · Open representative structure.

**Acceptance:** paste human SRC (UniProt P12931) and the architecture track reads
SH3 + SH2 + kinase N-to-C; comet appears in the Galaxy near the kinase clan; every result
row deep-links to its family card.

---

## 8. Phase 3 (~2.5 h): Grammarian + Prospector + Field Guide

**Grammarian:**
- Architecture strings from `pfam.sqlite` top-architecture table (pulled in the forge from
  InterPro protein-match sampling; keep the top ~2k architectures, that covers most of
  sequence space).
- Co-occurrence mini-graph per family (which domains travel with this one, edge weight =
  frequency), drawn with Canvas; tap a node to hop families. N-to-C ordering shown as
  directional chips ("SH3 → SH2 → Pkinase in 92% of co-occurrences").
- "Built like mine": takes the Oracle's parsed architecture, embeds the architecture string
  (mean of member centroids, order-weighted), returns nearest architectures with example
  proteins.

**Prospector:**
- Filtered DUF list (sortable by family size, taxonomic depth) on the same store.
- Per DUF: top-10 nearest annotated families in centroid space, shown as a hypothesis card
  ("DUF4784 sits nearest to Glyco_hydro families: candidate carbohydrate-active?").
  Wording stays scrupulously hypothesis-flavoured; these are leads, not annotations.
- Actions: Show in Galaxy (DUFs render as hollow points, a nice visual of the dark
  proteome) · Open structure (AlphaFold happily covers most DUF representatives).

**Field Guide:**
- Search-first screen: natural-language query embedded with the MiniLM Core ML model,
  cosine search over `desc_embeddings.bin` ("haem-binding families that dimerise" works
  offline). Recents + browse-by-clan below.
- Family card, full version: description, clan siblings, size, taxonomy sparkline, top
  architectures (chips deep-linking to Grammarian), structure peek, and the universal
  context-menu actions.

**Acceptance:** search "breaks down plastic" in Field Guide and reasonable hits appear
(cutinase/esterase-adjacent families); Prospector renders hypotheses for 10 random DUFs
without network access; Grammarian graph navigation never dead-ends.

---

## 9. Phase 4 (~2.5 h): Structure layer, cross-links, polish

**Structure layer (cross-cutting, this is what makes it a structural biologist's tool):**
- `MolViewer`: WKWebView wrapping the bundled single-file Mol* build; loads AlphaFold mmCIF
  fetched from `https://alphafold.ebi.ac.uk/api/prediction/{uniprot}` (then the `cifUrl`),
  cached to disk keyed by accession.
- Domain highlighting: JS bridge selects the Pfam domain residue range (UniProt numbering,
  direct mapping) and colours it `accentNova` against a translucent grey cartoon; multiple
  domains from an architecture get distinct hues matching the Oracle track lozenges.
- `StructurePeek`: small non-interactive snapshot in cards (Mol* render-to-image once,
  cached PNG); tap to expand to the full interactive viewer sheet with pLDDT colouring
  toggle. Offline: show the cached image with a quiet "structure needs network" note.
- Wire it everywhere: Oracle results, Galaxy chip, Grammarian nodes, Prospector hypotheses,
  Field Guide cards all reach the same viewer through `Destination.structure`.

**Cross-link audit:** walk every tab and confirm the universal context menu works in all
directions (Galaxy → card → Oracle → architecture → Grammarian → structure → back). No
dead ends, no tab-specific one-off navigation code.

**Platform pass:**
- iPad: three-column layout verified, pointer hover highlights Galaxy points, ⌘F/⌘1-5
  shortcuts wired.
- macOS: window resizing keeps the Galaxy crisp, menu bar carries Classify/Search/Appearance
  commands, dropping a `.fasta` on the dock icon opens Oracle pre-filled.
- visionOS scaffold: volumetric Galaxy renders the point cloud in RealityKit with gaze +
  pinch selection opening the family chip; remaining tabs open as flat windows reusing the
  shared views untouched. Polish (ornaments, hand-tracked comet placement) is the day-two
  half-day, not today.
- watchOS scaffold: `WatchConnectivity` receives the last Oracle result; watch face shows
  family name, clan colour, and confidence as a circular gauge; complication registered.

**Polish:**
- App icon placeholder (real one comes later via /marcs-vibe-icon).
- Empty states with personality ("The Oracle awaits a sequence"), error states that name the
  failing service (InterPro vs AlphaFold vs HMMER).
- Settings: appearance switcher, cache size + clear, model info (ESM-2 t6-8M, forge date),
  "About PfamIE" with marcdeller.com link.
- Performance pass: Instruments check that embedding runs on ANE, Galaxy holds 60 fps on
  device, cold launch under 1.5 s.
- README stub in repo root (full README later to the house standard).

**Acceptance (whole app):** on a physical iPhone, airplane mode ON: paste a sequence, get a
classification, fly the Galaxy, browse DUF hypotheses, semantic-search the Field Guide.
Airplane mode OFF: structures load and highlight domains. Both appearances look intentional.
Same flows repeat on iPad (split view) and Mac (sidebar + menu commands). visionOS simulator
renders the volumetric Galaxy and opens a family chip via gaze + pinch. Watch simulator
shows the last classification after a phone-side Oracle run. All five targets build clean.

---

## 10. Cut list (if the day runs hot, cut in this order)

1. VisionKit sequence scanning
2. HMMER online verification
3. watchOS complication (keep the synced glance view)
4. Grammarian "built like mine" (keep the co-occurrence graph)
5. Comet particle trail (keep the comet point)
6. visionOS gaze-selection niceties (keep the volumetric point cloud rendering)
7. SceneKit Galaxy → 2D Canvas Galaxy on iOS/macOS (same data, same taps)

Never cut: the Oracle, the appearance switcher, the structure layer, the cross-link router,
or the five-target build (empty shells are acceptable; broken targets are not).

## 11. Stretch goals (explicitly NOT today)

- ESM-2 t12-35M model tier with in-app model picker
- Exact parametric UMAP transform for comet placement
- visionOS day-two polish: ornaments, immersive-space Galaxy, hand-tracked comet placement
- On-watch k-NN against the centroid matrix (S9+ Neural Engine, phone ships the embedding)
- Handoff between platforms (start a scan on the phone, finish reading on the Mac)
- Per-residue attention maps on the architecture track
- Shareable family card images (branded, for the blog)
