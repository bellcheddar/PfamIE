#!/usr/bin/env bash
# Regenerate PfamIE.xcodeproj from project.yml.
#
# The project file is derived and gitignored. Everything that would normally be
# clicked into Xcode (targets, signing, the asset build phases) lives in
# project.yml so it survives regeneration.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null; then
    echo "xcodegen is not installed. brew install xcodegen" >&2
    exit 1
fi

# project.yml reads DEVELOPMENT_TEAM from the environment so this repo carries
# no account identifiers.
if [ -z "${APPLE_TEAM_ID:-}" ]; then
    echo "APPLE_TEAM_ID is not set. Run:" >&2
    echo "  set -a; source ~/.claude/skills/marcs-vibe-coding/credentials.env; set +a" >&2
    exit 1
fi

xcodegen generate --spec project.yml
echo "Generated PfamIE.xcodeproj"
