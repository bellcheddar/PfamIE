# Shipping PfamIE to TestFlight

Everything here is scripted except two steps that Apple's API genuinely cannot
do. Both are one-off, and both are flagged by the tooling with the exact thing
to click.

## What is already done

| | |
|---|---|
| Team | Read from `APPLE_TEAM_ID` in the environment, so no account identifier is committed |
| Bundle IDs | `com.mdeller.pfamie`, `.watchkitapp`, `.watchkitapp.widget`, all registered over the API |
| Provisioning profiles | Five, created and installed over the API |
| Signing | Release signs manually against `Apple Distribution`; Debug stays automatic, so a device build from Xcode still just works. Configured in `project.yml`, so it survives project regeneration |
| Archive | `./Tools/archive.sh [ios\|macos\|visionos]` |
| Verification | `./Tools/verify-archive.sh <archive>`, negative-tested |
| Upload | `./Tools/upload.sh <archive>` |

The macOS and visionOS archives have been produced, signed for distribution and
verified complete end to end, and both builds are uploaded.

## Step 1: create the App Store Connect app record (done)

> This has been done for PfamIE, and the listing is fully populated. The
> section is kept because it is the step no API can perform, and the next app
> will need it.


Apple forbids this over the API:

```
POST /v1/apps -> 403 FORBIDDEN_ERROR
"The resource 'apps' does not allow 'CREATE'.
 Allowed operations are: GET_COLLECTION, GET_INSTANCE, UPDATE"
```

It also carries a decision that is genuinely yours: the **App Store name is
globally unique across the entire store** and may be taken. "PfamIE" is
unusual enough to be likely free, but that has to be checked there.

1. <https://appstoreconnect.apple.com> -> Apps -> **+** -> New App
2. Platforms: iOS (add macOS and visionOS later if you want them in the same record)
3. Bundle ID: `com.mdeller.pfamie` (already registered, it will appear in the list)
4. SKU: anything unique, `pfamie-001` is fine
5. Name: whatever is available

Check it took:

```bash
set -a; source ~/.claude/skills/marcs-vibe-coding/credentials.env; set +a
.venv/bin/python Tools/asc_api.py status
```

**Recognise the symptom, because it blames the wrong thing.** Uploading before
the record exists gives:

```
ERROR: Cannot determine the Apple ID from Bundle ID 'com.mdeller.pfamie'
       and platform 'IOS'. (19)
```

That is a missing app record, not a bundle-ID problem. `upload.sh` detects that
exact string and says so.

## Step 2: create the App Group (outstanding, watch only)

The complication reads the last classification from an App Group shared with
the watch app. Without it the widget extension has its own container and the
complication shows a placeholder forever.

App Groups are a Developer Portal concept and App Store Connect's API has no
`/appGroups` resource, so the group itself must be created by hand. The
`APP_GROUPS` **capability** on both bundle IDs is already enabled over the API;
only the group and its association are manual.

1. <https://developer.apple.com/account/resources/identifiers/list/applicationGroup>
2. **+** -> App Groups -> Description `PfamIE`, Identifier `group.com.mdeller.pfamie`
3. Then, under Identifiers, for **both** `com.mdeller.pfamie.watchkitapp` and
   `com.mdeller.pfamie.watchkitapp.widget`: edit -> App Groups -> Configure ->
   tick `group.com.mdeller.pfamie`
4. Regenerate the profiles so they carry it:

```bash
.venv/bin/python Tools/asc_api.py refresh-profiles
```

Until this is done the iOS archive fails with *"Provisioning profile ... doesn't
support the group.com.mdeller.pfamie App Group"*. The macOS archive is
unaffected and works today.

If you would rather not bother, deleting the `PfamIE-watchOS-Complication`
target from `project.yml` and the App Group from both entitlements files
removes the requirement entirely, at the cost of the complication.

## Then

```bash
set -a; source ~/.claude/skills/marcs-vibe-coding/credentials.env; set +a
./Tools/archive.sh ios
./Tools/verify-archive.sh build/archives/PfamIE-ios.xcarchive
./Tools/upload.sh build/archives/PfamIE-ios.xcarchive
```

`upload.sh` runs the verifier itself before exporting, so a bundle missing its
Core ML models cannot reach Apple. Point `altool` at the key rather than
copying it: it only searches `./private_keys`, `~/private_keys`,
`~/.private_keys` and `~/.appstoreconnect/private_keys`, and the key is in none
of them. The script sets `API_PRIVATE_KEYS_DIR` for you.

## A note on the identifier

The widget extension is `com.mdeller.pfamie.watchkitapp.widget`, not
`.complication`. **Apple reserves "complication" in the App ID namespace** and
rejects it at any depth with "An App ID with Identifier ... is not available",
while `.widget` and `.extension` under the same parent are accepted. The error
names the identifier rather than the reason, so it is worth knowing.
