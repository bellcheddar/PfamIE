# PfamIE: working notes

On-device Pfam family inference for iOS, iPadOS, macOS, visionOS and watchOS.
Read `README.md` for what it is. This file is for how to work on it.

## Hard rules

1. **Do not quote the held-out seed accuracy as the app's accuracy.** The same
   pipeline scores 0.75 top-1 on held-out Pfam seed sequences and 0.49 on real
   UniProt proteins. Seeds are trimmed to domain boundaries and drawn from the
   alignments the centroids were built from, so they measure the index against
   its own kind. Every user-facing number comes from
   `forge/stage_calibrate_real.py`. A test fails the build if the shipped
   calibration ever matches the seed-fitted one.

2. **Parity between two implementations is not correctness.** The Core ML model
   once whitened an un-normalised vector while `mu` and `W` had been fitted on
   unit-length ones. Torch and Core ML agreed to a cosine of 0.99999 throughout,
   because both ran the same wrong recipe, and lysozyme classified as a coiled
   coil. Any change to the embedding path must be checked end to end against the
   shipped index (`verify_against_index` in `stage_coreml.py`), never only
   against another implementation of the same idea.

3. **Check the Neural Engine, not just the CPU.** Core ML runs float16 on the
   ANE and float32 on the CPU. A whitened vector whose sum of squares overflows
   float16 returned all zeros on the ANE while the CPU path looked perfect.
   `stage_coreml.py` asserts parity on `ComputeUnit.ALL`.

4. **`BUILD SUCCEEDED` says nothing about the bundle.** Run
   `Tools/verify-bundle.sh` on the built app. It is negative-tested: strip a
   model from a copy and it must exit 1.

5. **Run it and look at it.** Three real faults (a missing
   `CFBundleExecutable`, a light-mode launch that turned the Galaxy white, a
   Prospector full of characterised families) passed every test and every build.
   Use the DEBUG launch arguments and `xcrun simctl io booted screenshot`:

       xcrun simctl launch booted com.mdeller.pfamie -PfamIETab prospector
       xcrun simctl launch booted com.mdeller.pfamie -PfamIESequence KVFGRC...
       xcrun simctl launch booted com.mdeller.pfamie -PfamIEFamily PF00017
       xcrun simctl launch booted com.mdeller.pfamie -PfamIEQuery "breaks down plastic"

6. **Keep going through the phases.** Commit, push, start the next one. Pause
   only for a decision that is genuinely Marc's: a scientific default, a
   licence, anything destructive or outward-facing, anything needing `sudo`, or
   the App Store Connect app record. Finishing a phase is not a question.

## Layout

| Path | What |
|---|---|
| `forge/` | Python. Builds every shipped asset. Run before building the app. |
| `PfamIEKit/` | SwiftPM package: engine, data, and all shared views. |
| `Apps/` | Thin per-platform targets. |
| `project.yml` | XcodeGen spec. **The `.xcodeproj` is derived and gitignored.** Never hand-edit it; run `Tools/generate-project.sh`. |
| `assets/` | Forge output, gitignored. About 148 MB. |

The watch companion is excluded from the phone and desktop views by
`#if !os(watchOS)`. It carries no assets and no model: the phone classifies and
sends a summary over WatchConnectivity.

## Apple

Team and bundle-ID convention are settled in the `marcs-vibe-coding` skill,
never ask. The team is read from `APPLE_TEAM_ID` in the environment so no
account identifier lives in this public repo:

    set -a; source ~/.claude/skills/marcs-vibe-coding/credentials.env; set +a
Release signs manually against `Apple Distribution`; Debug stays automatic.
Three things have no API: the app record, App Groups (create *and* assign, both
manual), and App Privacy. See `docs/TESTFLIGHT.md`.

## Things already measured, so do not re-litigate them

| Question | Answer | Where |
|---|---|---|
| Whitening the centroids? | Yes: top-1 0.514 to 0.715, and the map stops being a featureless ball. alpha 1.0, eps 1e-5 (on the plateau, caps amplification at 34x). | `assets/build/whiten_sweep2.log` |
| Sequences per centroid? | 16, chosen by a stratified sweep across the alignment. Choosing by closeness to median length selects near-duplicates. | `stage_metadata.py` |
| Whole sequence or windows? | Multi-scale windows: 0.285 whole, 0.425 at one width, 0.535 at four. | `benchmark_multiscale.py` |
| Are there hub families? | No. The most connected family is nearest to 19 of 30,031, and the top 15 absorb 0.6% of nearest-neighbour slots. | measured 2026-08-27 |
| int8 matrices? | Done. Free (top-1 0.7150 against 0.7149); centroids and descriptions both quantised. | `assets/build/int8_test.log` |
| A bigger model? | Done: t12-35M shipped. Real top-1 0.430 to 0.492, multi-domain recall 0.358 to 0.478 at higher precision, for 5.2x inference. t30-150M untested. | `assets/build_t12/evaluation.json` |
| Boundary refinement? | Tried twice, both worse. Narrow tiles: IoU 0.44 to 0.19. Per-residue segmentation: recall up, precision 0.76 to 0.41. The limit is detection, not localisation. | `assets/build/bnd_multi_*.log` |

## Forge notes

- Python 3.12. numba (via umap-learn) and coremltools are not reliable on 3.14.
- `stage_interpro.py ida` takes about 100 minutes and is resumable: it appends
  to a JSON-lines file and skips accessions already present.
- Everything except architectures and family sizes comes from the Pfam release
  flatfiles, not the API. One 52 MB download replaces 30,031 requests.
- `stage_metadata.py` is deterministic. If you change only the DUF rule, the
  centroid sequences are unchanged and nothing needs re-embedding: hash
  `centroid_seqs` before and after to confirm.
