#!/usr/bin/env bash
# Build the gem from local source and install it.
# Use this to test changes before pushing to main.
set -euo pipefail

script_dir=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
pkg_dir="$repo_root/pkg"

for cmd in ruby gem bundle; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing required command: $cmd" >&2; exit 1; }
done

mkdir -p "$pkg_dir"
cd "$repo_root"

bundle install

build_output=$(gem build wisco.gemspec)
printf '%s\n' "$build_output"

gem_file=$(printf '%s\n' "$build_output" | awk -F': ' '/^  File: / { print $2 }')
if [[ -z "$gem_file" || ! -f "$repo_root/$gem_file" ]]; then
  echo "Unable to locate built gem artifact." >&2
  exit 1
fi

artifact_path="$pkg_dir/$gem_file"
mv -f "$repo_root/$gem_file" "$artifact_path"

gem install "$artifact_path" --force
printf 'Installed %s from local build\n' "$artifact_path"
printf 'Verify with: wisco --version\n'
