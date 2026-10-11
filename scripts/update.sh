#!/usr/bin/env bash
#
# Regenerate pkgs/cua-driver/source.json from the Homebrew `cuadriver` cask,
# plus the matching agent skill pack from the same upstream release.
# Homebrew's JSON API carries the cask's resolved {version, url, sha256}, kept
# current by Homebrew's autobump; the URL must still point at trycua/cua's own
# GitHub release. Prints a final line of `changed` or `unchanged` for CI.
set -euo pipefail

cd "$(dirname "$0")/.."

CASK_API="https://formulae.brew.sh/api/cask/cuadriver.json"
SRC_JSON="pkgs/cua-driver/source.json"
URL_PREFIX="https://github.com/trycua/cua/releases/download/cua-driver-rs-v"

cask="$(curl -fsSL --retry 3 --retry-delay 2 "$CASK_API")"

version="$(jq -r '.version // empty' <<<"$cask")"
url="$(jq -r '.url // empty' <<<"$cask")"
sha_hex="$(jq -r '.sha256 // empty' <<<"$cask")"

if [ -z "$version" ] || [ -z "$url" ] || [ -z "$sha_hex" ]; then
  echo "ERROR: could not read version/url/sha256 from $CASK_API" >&2
  exit 1
fi

# Fail loud on upstream format changes instead of writing a broken source.json.
if ! printf '%s' "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "ERROR: unexpected version format: $version" >&2
  exit 1
fi
expected_url="${URL_PREFIX}${version}/cua-driver-rs-${version}-darwin-universal.tar.gz"
if [ "$url" != "$expected_url" ]; then
  echo "ERROR: cask URL is not trycua/cua's darwin-universal release asset:" >&2
  echo "  got:      $url" >&2
  echo "  expected: $expected_url" >&2
  exit 1
fi
if ! printf '%s' "$sha_hex" | grep -qE '^[0-9a-f]{64}$'; then
  echo "ERROR: sha256 is not a 64-char hex digest: $sha_hex" >&2
  exit 1
fi

# Homebrew publishes hex; Nix wants SRI.
sri="$(nix hash convert --hash-algo sha256 --to sri "$sha_hex")"

# The agent skill pack ships in the same upstream release. Take its digest from
# the release's SHA256SUMS so the skill always matches the packaged driver.
release="${URL_PREFIX}${version}"
skills_name="cua-driver-rs-v${version}-skills.tar.gz"
skills_url="${release}/${skills_name}"
skills_hex="$(curl -fsSL --retry 3 --retry-delay 2 "${release}/SHA256SUMS" \
  | awk -v name="$skills_name" '$2 == name || $2 == "*" name { print $1 }')"
if ! printf '%s' "$skills_hex" | grep -qE '^[0-9a-f]{64}$'; then
  echo "ERROR: no sha256 for $skills_name in the release SHA256SUMS" >&2
  exit 1
fi
skills_sri="$(nix hash convert --hash-algo sha256 --to sri "$skills_hex")"

new="$(jq -n --arg version "$version" --arg url "$url" --arg sha256 "$sri" \
  --arg skills_url "$skills_url" --arg skills_sha256 "$skills_sri" \
  '{version: $version, url: $url, sha256: $sha256,
    skills: {url: $skills_url, sha256: $skills_sha256}}')"
old="$(cat "$SRC_JSON" 2>/dev/null || echo '{}')"

if [ "$(jq -S . <<<"$new")" = "$(jq -S . <<<"$old")" ]; then
  echo "already at version $version"
  echo "unchanged"
else
  printf '%s\n' "$new" >"$SRC_JSON"
  echo "updated to version $version"
  echo "changed"
fi
