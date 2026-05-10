#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "$script_dir/.." && pwd)
pkg_dir="$repo_root/pkg"

# Fail early if the local Ruby toolchain is not available.
for command in ruby gem bundle git; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing required command: $command" >&2
    exit 1
  fi
done

mkdir -p "$pkg_dir"

cd "$repo_root"
bundle install

build_output=$(gem build wisco.gemspec)
printf '%s\n' "$build_output"

# Extract the generated gem filename from RubyGems build output.
gem_file=$(printf '%s\n' "$build_output" | awk -F': ' '/^  File: / { print $2 }')

# Stop if the build output did not point to a real gem artifact.
if [[ -z "$gem_file" || ! -f "$repo_root/$gem_file" ]]; then
  echo "Unable to locate built gem artifact." >&2
  exit 1
fi

# Move the freshly built gem into pkg so install uses the packaged artifact.
artifact_path="$pkg_dir/$gem_file"
mv -f "$repo_root/$gem_file" "$artifact_path"

gem push "$artifact_path"

# Tag the current commit with the built gem version.
version="${gem_file#wisco-}"
version="${version%.gem}"
tag_name="$version"


# Tag the version after a build
# Check if the tag already exists to avoid errors on repeated builds of the same version.
if git rev-parse -q --verify "refs/tags/$tag_name" >/dev/null; then
  printf 'Git tag %s already exists; skipping tag creation.\n' "$tag_name"
else
  git tag "$tag_name"
  git push origin "$tag_name"
  printf 'Created git tag %s\n' "$tag_name"
fi

gem install "$artifact_path" --force

# Report the final artifact path and the simplest verification command.
printf 'Built and installed %s\n' "$artifact_path"
printf 'Verify with: wisco --version\n'