#!/usr/bin/env bash
# Check that a built PfamIE app actually contains what it needs to work.
#
# BUILD SUCCEEDED says nothing about the contents. An app that ships without
# its Core ML models or its centroid matrix builds cleanly, signs cleanly, and
# cannot do the one thing it exists to do. Negative-test this script by
# deleting a file from a bundle: it must fail.
set -uo pipefail

APP="${1:?usage: verify-bundle.sh /path/to/PfamIE.app}"
if [ -d "$APP/Contents/Resources" ]; then
    RES="$APP/Contents/Resources"          # macOS
else
    RES="$APP"                              # iOS, visionOS, watchOS
fi

fail=0
note() { printf '  %-42s %s\n' "$1" "$2"; }

check_file() {
    local path="$1" min="$2"
    if [ ! -e "$path" ]; then
        note "$(basename "$path")" "MISSING"; fail=1; return
    fi
    local size
    size=$(du -sk "$path" | cut -f1)
    if [ "$size" -lt "$min" ]; then
        note "$(basename "$path")" "TOO SMALL (${size} kB < ${min} kB)"; fail=1; return
    fi
    note "$(basename "$path")" "$(du -sh "$path" | cut -f1)"
}

echo "Verifying $(basename "$APP")"
echo "Models:"
check_file "$RES/PfamIEProteinEmbedder.mlmodelc" 8000
check_file "$RES/PfamIETextEmbedder.mlmodelc"    8000

echo "Data:"
for f in manifest.json pfam.sqlite centroids.bin umap3d.bin desc_emb.bin; do
    if [ -e "$RES/bundle/$f" ]; then base="$RES/bundle"; else base="$RES"; fi
    case "$f" in
        pfam.sqlite)   min=40000 ;;
        centroids.bin) min=15000 ;;
        desc_emb.bin)  min=15000 ;;
        umap3d.bin)    min=200   ;;
        *)             min=1     ;;
    esac
    check_file "$base/$f" "$min"
done

echo "Structure viewer:"
if [ -e "$RES/bundle/molstar" ]; then MOL="$RES/bundle/molstar"; else MOL="$RES/molstar"; fi
check_file "$MOL/molstar.js" 3000

echo "Icon:"
# The compiled icon at the bundle root, not the .appiconset: an empty
# appiconset still builds, and the app ships with a blank tile.
if [ -f "$RES/AppIcon.icns" ]; then
    note "AppIcon.icns" "$(du -sh "$RES/AppIcon.icns" | cut -f1)"
elif ls "$RES"/AppIcon*.png >/dev/null 2>&1; then
    for icon in "$RES"/AppIcon60x60@2x.png "$RES"/AppIcon76x76@2x~ipad.png; do
        if [ -f "$icon" ]; then
            note "$(basename "$icon")" "$(du -sh "$icon" | cut -f1)"
        else
            note "$(basename "$icon")" "MISSING"; fail=1
        fi
    done
else
    note "app icon" "MISSING"; fail=1
fi

echo "Signing:"
authority=$(codesign -dvv "$APP" 2>&1 | grep "^Authority=" | head -1)
if [ -n "$authority" ]; then note "authority" "${authority#Authority=}"; else note "authority" "unsigned (fine for a debug build)"; fi

echo
if [ "$fail" -eq 0 ]; then
    echo "OK: $(du -sh "$APP" | cut -f1) bundle, everything present."
else
    echo "FAILED: the bundle is missing something it needs to run." >&2
fi
exit "$fail"
