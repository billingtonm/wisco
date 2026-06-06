# Building and Releasing Wisco

## Release (publish to RubyGems)

1. Bump the version in `lib/wisco/version.rb`
2. Commit and merge to `main`
3. GitHub Actions (`.github/workflows/release.yml`) will automatically:
   - Detect the version change
   - Build the gem
   - Publish to RubyGems
   - Create a git tag and GitHub Release

## Install after release

Once the GitHub Action completes, install the published gem locally:

```bash
./scripts/install_rubygems.sh
```

This reads the version from `lib/wisco/version.rb` and installs it from RubyGems.
It will retry for up to 5 minutes if the gem is not yet indexed.

## Local install (without releasing)

To build and install from local source without publishing:

```bash
./scripts/install_local.sh
```

## Verify

```bash
wisco --version
```
