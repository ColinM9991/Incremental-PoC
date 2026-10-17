#!/usr/bin/env bash
# Works out the next version from the VERSION file and the existing tags.
#
# Usage: derive-version.sh <public|tester> [version-file]
set -euo pipefail

release_type="${1:?release type required (public or tester)}"
version_file="${2:-VERSION}"

fail() { echo "::error::$*" >&2; exit 1; }

case "$release_type" in
  public|tester) ;;
  *) fail "Release type must be 'public' or 'tester', got '$release_type'" ;;
esac

[[ -f "$version_file" ]] || fail "$version_file not found"

# Read the major and minor from the version file
num='(0|[1-9][0-9]*)'
read_key() {
  local value
  value="$(yq -r ".$1 // \"\"" "$version_file")" || fail "$version_file is not valid YAML"
  [[ "$value" =~ ^${num}$ ]] || fail "$version_file needs a whole number for '$1', got '$value'"
  echo "$value"
}
major="$(read_key major)"
minor="$(read_key minor)"
major_minor="${major}.${minor}"

stable_tags="$(git tag --list 'v*' | grep -E "^v${num}\.${num}\.${num}$" || true)"

# VERSION must never go backwards from the highest stable release.
highest="$(sort -V <<< "$stable_tags" | tail -n 1)"
if [[ -n "$highest" ]]; then
  IFS=. read -r h_major h_minor _ <<< "${highest#v}"
  if (( major < h_major || (major == h_major && minor < h_minor) )); then
    fail "$version_file is $major_minor but $highest has already been released"
  fi
fi

# Next patch for this MAJOR.MINOR, or 0 when nothing has been released for it yet.
last_patch="$(grep -E "^v${major}\.${minor}\.[0-9]+$" <<< "$stable_tags" \
  | sed -E 's/^v[0-9]+\.[0-9]+\.//' | sort -n | tail -n 1 || true)"
if [[ -n "$last_patch" ]]; then
  patch=$(( last_patch + 1 ))
else
  patch=0
fi

version="${major}.${minor}.${patch}"
is_prerelease=false

# Non-public builds become X.Y.<next patch>-<release_type>.N, counting up from existing tags.
if [[ "$release_type" != public ]]; then
  release_type_tag=$([[ "$release_type" == candidate ]] && echo "rc" || echo "dev")
  last_dev="$(git tag --list "v${version}-${release_type_tag}.*" \
    | sed -nE "s/^v${major}\.${minor}\.${patch}-${release_type_tag}\.([0-9]+)$/\1/p" | sort -n | tail -n 1)"
  version="${version}-${release_type_tag}.$(( ${last_dev:-0} + 1 ))"
  is_prerelease=true
fi

baseline="${major}.${minor}.0"
baseline_exists=false
git rev-parse -q --verify "refs/tags/v${baseline}" > /dev/null && baseline_exists=true

is_baseline=false
[[ "$version" == "$baseline" ]] && is_baseline=true

# Only public patch releases get an incremental.
needs_incremental=false
[[ "$is_prerelease" == false && "$is_baseline" == false ]] && needs_incremental=true

outputs="version=${version}
tag=v${version}
baseline=${baseline}
baseline-tag=v${baseline}
baseline-exists=${baseline_exists}
is-prerelease=${is_prerelease}
needs-incremental=${needs_incremental}"

echo "$outputs"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "$outputs" >> "$GITHUB_OUTPUT"
fi
