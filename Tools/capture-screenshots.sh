#!/usr/bin/env bash
# Capture App Store screenshots from a simulator.
#
# Drives the app through the DEBUG launch arguments, because there is no other
# way to put a particular tab and a particular result on screen from outside.
#
#   ./Tools/capture-screenshots.sh <device-udid> <output-dir> [ios|visionos]
set -euo pipefail
cd "$(dirname "$0")/.."

UDID="${1:?usage: capture-screenshots.sh <udid> <out-dir> [platform]}"
OUT="${2:?}"
PLATFORM="${3:-ios}"
BUNDLE="com.mdeller.pfamie"
mkdir -p "$OUT"

SRC="MGSNKSKPKDASQRRRSLEPAENVHGAGGGAFPASQTPSKPASADGHRGPSAAFAPAAAEPKLFGGFNSSDTVTSPQRAGPLAGGVTTFVALYDYESRTETDLSFKKGERLQIVNNTEGDWWLAHSLSTGQTGYIPSNYVAPSDSIQAEEWYFGKITRRESERLLLNAENPRGTFLVRESETTKGAYCLSVSDFDNAKGLNVKHYKIRKLDSGGFYITSRTQFNSLQQLVAYYSKHADGLCHRLTTVCPTSKPQTQGLAKDAWEIPRESLRLEVKLGQGCFGEVWMGTWNGTTRVAIKTLKPGTMSPEAFLQEAQVMKKLRHEKLVQLYAVVSEEPIYIVTEYMSKGSLLDFLKGETGKYLRLPQLVDMAAQIASGMAYVERMNYVHRDLRAANILVGENLVCKVADFGLARLIEDNEYTARQGAKFPIKWTAPEAALYGRFTIKSDVWSFGILLTELTTKGRVPYPGMVNREVLDQVERGYRMPCPPECPESLHDLMCQCWRKEPEERPTFEYLQAFLEDYFTSTEPQYQPGENL"

settle() { local n=0; until [ $n -ge "${1:-25}" ]; do n=$((n+1)); sleep 1; done; }

shot() {
    local name="$1"; shift
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    xcrun simctl launch "$UDID" "$BUNDLE" "$@" >/dev/null
    settle "${SETTLE:-30}"
    xcrun simctl io "$UDID" screenshot --type=png "$OUT/$name.png" >/dev/null 2>&1
    echo "  $name.png  $(sips -g pixelWidth -g pixelHeight "$OUT/$name.png" 2>/dev/null \
        | awk '/pixel/{printf "%s ", $2}')"
}

echo "Capturing from $UDID into $OUT"
shot "1-galaxy"
shot "2-oracle"     -PfamIESequence "$SRC"
shot "3-fieldguide" -PfamIEQuery "breaks down plastic"
shot "4-grammarian" -PfamIEFamily PF00017
shot "5-prospector" -PfamIETab prospector
