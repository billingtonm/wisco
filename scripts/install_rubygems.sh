#!/usr/bin/env bash
# Install the published wisco gem from RubyGems.
# The target version is read from lib/wisco/version.rb.
# Retries for up to 5 minutes to handle the ~30-60s RubyGems indexing delay
# after a fresh release.
set -euo pipefail

script_dir=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)

command -v gem >/dev/null 2>&1 || { echo "Missing required command: gem" >&2; exit 1; }

version=$(ruby -e "require_relative '$repo_root/lib/wisco/version'; puts Wisco::VERSION")
printf 'Installing wisco %s from RubyGems...\n' "$version"

max_attempts=10
attempt=0
until gem install wisco -v "$version" --force 2>/dev/null; do
  attempt=$((attempt + 1))
  if [[ $attempt -ge $max_attempts ]]; then
    printf 'wisco %s not yet available on RubyGems after %d attempts.\n' \
      "$version" "$max_attempts" >&2
    exit 1
  fi
  printf 'Not yet available — retrying in 30s (attempt %d/%d)...\n' \
    "$attempt" "$max_attempts"
  sleep 30
done

printf 'Installed wisco %s from RubyGems\n' "$version"
printf 'Verify with: wisco --version\n'
