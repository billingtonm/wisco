# Installing Wisco

## WSL (recommended)

### Prerequisites

1. Ruby 2.7.x in WSL — install via rbenv or rvm if not already present:

   ```bash
   # rbenv (recommended)
   rbenv install 2.7.6
   rbenv global 2.7.6   # or local, per project
   ```

2. Bundler:

   ```bash
   gem install bundler
   ```

3. Native extensions required by `workato-connector-sdk` — ensure build tools are present:

   ```bash
   sudo apt-get install -y build-essential libssl-dev
   ```

### Build and install

From a WSL terminal, navigate to the project directory and run:

```bash
# Go to wisco source directory
cd "/path/to/wisco"

# Build the gem into ./pkg and install it locally
./scripts/build_install.sh
```

The script runs `bundle install`, builds the gem from the repo root, moves the
generated artifact into `./pkg`, and installs that exact file locally.

Manual fallback:

```bash
# Install dependencies (required for native extensions to compile)
bundle install

# Build the gem from the repo root
gem build wisco.gemspec

# Move the built gem into ./pkg and install it
mv wisco-*.gem ./pkg/
gem install ./pkg/wisco-*.gem --force
```

### Verify

```bash
wisco --version
# => Wisco (Workato Connector SDK Companion) v0.1.0
```

### Updating after code changes

Rebuild and reinstall:

```bash
./scripts/build_install.sh
```

---

## Windows (dev mode)

The root `wisco.rb` script and `wisco.bat` wrapper remain as a Windows dev entry point.
No installation required — run directly from the project directory:

```bat
ruby wisco.rb <command>
```

Or, add the project directory to your `PATH` so `wisco.bat` is found:

1. Open **System Properties → Environment Variables**
2. Under **User variables**, edit `Path`
3. Add the full path to this project directory
4. Open a new terminal and run `wisco <command>`
