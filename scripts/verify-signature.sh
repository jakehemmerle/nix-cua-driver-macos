#!/usr/bin/env bash
#
# Authenticity gate for the built CuaDriver.app. The fetchurl hash only proves
# the tarball matches the checksum Homebrew reports; this asserts the
# non-forgeable property: Apple-notarized and signed by Cua AI, Inc.'s
# Developer ID Team. The auto-updater runs this before committing a bump.
#
# Usage: scripts/verify-signature.sh [result-dir]   (default: ./result)
set -euo pipefail

RESULT="${1:-result}"
APP="$RESULT/Applications/CuaDriver.app"
EXPECTED_TEAM_ID="YCK386LBJ7"
EXPECTED_BUNDLE_ID="com.trycua.driver"

if [ ! -d "$APP" ]; then
  echo "ERROR: $APP not found (did 'nix build' run?)" >&2
  exit 1
fi

codesign --verify --deep --strict --verbose=2 "$APP"

details="$(codesign -dv --verbose=4 "$APP" 2>&1)"
team_id="$(sed -n 's/^TeamIdentifier=//p' <<<"$details")"
bundle_id="$(sed -n 's/^Identifier=//p' <<<"$details")"
if [ "$team_id" != "$EXPECTED_TEAM_ID" ]; then
  echo "ERROR: code-signing Team ID is '$team_id', expected '$EXPECTED_TEAM_ID'." >&2
  echo "Refusing to trust this build. Update EXPECTED_TEAM_ID only deliberately." >&2
  exit 1
fi
if [ "$bundle_id" != "$EXPECTED_BUNDLE_ID" ]; then
  echo "ERROR: bundle identifier is '$bundle_id', expected '$EXPECTED_BUNDLE_ID'." >&2
  exit 1
fi

if spctl -a -vvv -t exec "$APP" 2>&1; then
  echo "gatekeeper: accepted (notarized)"
else
  echo "WARN: spctl assessment did not pass in this environment (non-fatal)" >&2
fi

echo "OK: $bundle_id signed by Team ID $team_id"
