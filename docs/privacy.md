---
title: PfamIE Privacy Policy
---

# PfamIE Privacy Policy

**Last updated: 27 August 2026**

PfamIE collects nothing. There are no accounts, no analytics, no advertising,
no tracking identifiers, and no telemetry of any kind. Nothing you type into
the app is stored anywhere except on your own device.

This is not a policy written around a data practice. It is a description of how
the app is built: the protein language model, the family index, the domain
architecture data and the search index are all bundled with the app and run on
your device, so the app has nothing to send.

## What stays on your device

Everything, by default:

- Sequences you paste, import or scan with the camera
- Every classification, domain architecture and search you run
- Your settings, including your appearance preference
- Any structures already downloaded and cached

Sequences are never written to disk by PfamIE. They exist in memory while you
are working with them and are gone when you close the app.

## The two things that use the network

Both are optional. Neither is on by default, and the app tells you before it
does either.

### 1. Predicted structures from AlphaFold

When you open a structure, PfamIE asks the AlphaFold Protein Structure Database
at EMBL-EBI for the model of a UniProt accession, and caches the result on your
device so it is not asked for twice.

**What is sent:** a UniProt accession number, such as `P12931`. That accession
comes from the public Pfam data bundled with the app. **Your sequence is never
sent.** If you never open a structure, nothing is ever requested.

You can clear the cache at any time in Settings.

### 2. Verification with InterProScan (opt in)

The Oracle can check its answer against InterProScan 5 at EMBL-EBI, which is
the authoritative Pfam assignment PfamIE approximates.

This is the only feature that sends a sequence anywhere. It is off unless you
enter your own email address in Settings, and it asks for confirmation every
single time, naming what it is about to send.

**What is sent:** the amino-acid sequence you are classifying, and the email
address you entered. EMBL-EBI require an email address for job submission so
they can contact you about the job. Their use of it is governed by the
[EMBL-EBI terms of use](https://www.ebi.ac.uk/about/terms-of-use).

Your email address is stored only on your device, only so you do not have to
retype it, and is sent only to EMBL-EBI and only when you confirm a
verification.

## Camera

If you use the camera to read a printed sequence, the image is processed
entirely on your device by Apple's on-device text recognition. No image and no
recognised text leaves the device. PfamIE does not save photographs.

## Apple Watch

If you use the watch companion, the last classification summary (a family name,
an accession, a confidence and a residue count) is sent from your iPhone to
your Apple Watch over Apple's encrypted device-to-device link. **The sequence
itself is not sent to the watch.** It does not pass through any server.

## Children

PfamIE is a scientific reference tool. It is not directed at children and
collects no data from anyone, of any age.

## Changes

If this policy ever changes, the date at the top will change with it and the
history will be visible in the
[public repository](https://github.com/bellcheddar/PfamIE/commits/main/docs/privacy.md).

## Contact

Marc C. Deller, D.Phil.
[marc@marcdeller.com](mailto:marc@marcdeller.com)
[marcdeller.com](https://marcdeller.com)
