#!/usr/bin/env bash
# Lists every file touched by any commit between two refs, split into files to ship and files to delete.
#
# Using every touched file rather than the net diff means the patch is correct
# whichever X.Y.z the user has installed. A file added in 2.2.3 and removed in
# 2.2.5 lands in the delete list, so someone on 2.2.3 gets it cleaned up.
#
# Usage: detect-changes.sh <base-ref> <head-ref> <path> <output-dir>
set -euo pipefail

base="${1:?base ref required}"
head="${2:?head ref required}"
path="${3:?path required}"
out_dir="${4:?output dir required}"

fail() { echo "::error::$*" >&2; exit 1; }

git rev-parse -q --verify "${base}^{commit}" > /dev/null || fail "Base ref '$base' not found"
git rev-parse -q --verify "${head}^{commit}" > /dev/null || fail "Head ref '$head' not found"

mkdir -p "$out_dir"
touched="$(mktemp)"
present="$(mktemp)"
trap 'rm -f "$touched" "$present"' EXIT

# --no-renames lists a rename as the old path and the new path, so the old one
# ends up in the delete list. --diff-merges=first-parent picks up anything that
# only changed while resolving a merge.
git -c core.quotepath=off log --format= --name-only --no-renames \
  --diff-merges=first-parent "${base}..${head}" -- "$path" \
  | sed '/^$/d' | LC_ALL=C sort -u > "$touched"

git -c core.quotepath=off ls-tree -r --name-only "$head" -- "$path" \
  | LC_ALL=C sort -u > "$present"

# Make paths relative to the aircraft folder, which is how the app sees them.
strip_prefix() {
  if [[ "$path" == "." ]]; then cat; else
    awk -v p="${path%/}/" 'index($0, p) == 1 { print substr($0, length(p) + 1) }'
  fi
}

LC_ALL=C comm -12 "$touched" "$present" | strip_prefix > "$out_dir/changed.txt"
LC_ALL=C comm -23 "$touched" "$present" | strip_prefix > "$out_dir/deleted.txt"

changed_count="$(wc -l < "$out_dir/changed.txt" | tr -d ' ')"
deleted_count="$(wc -l < "$out_dir/deleted.txt" | tr -d ' ')"

echo "Changed: $changed_count, deleted: $deleted_count"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "changed-count=${changed_count}"
    echo "deleted-count=${deleted_count}"
    echo "changed=$(jq -Rsc 'split("\n") | map(select(length > 0))' "$out_dir/changed.txt")"
    echo "deleted=$(jq -Rsc 'split("\n") | map(select(length > 0))' "$out_dir/deleted.txt")"
  } >> "$GITHUB_OUTPUT"
fi
