# Wisco — Workato Connector SDK Companion

Wisco is a Ruby CLI gem for developing and managing [Workato](https://www.workato.com) custom connectors. It wraps the [Workato Connector SDK CLI](https://docs.workato.com/developing-connectors/sdk/cli.html) and adds conventions for fixture management, schema inspection, and platform deployment.

## Installation

Build and install the gem locally:

```bash
gem build wisco.gemspec
gem install wisco-*.gem
```

Then verify:

```bash
wisco --version
```

## Requirements

- Ruby `2.7.6`
- `workato-connector-sdk 1.3.19`
- `activesupport ~> 7.0.0`

## Quick Start

From a Workato connector project directory:

```bash
wisco init          # detect connector, write config, deploy project files
wisco list all      # inspect connector structure
wisco fixtures actions.get_user   # generate fixture templates
# edit fixtures/actions/get_user/execute_input.json (remove the sentinel line)
wisco exec actions.get_user       # run the action against live credentials
```

### Typical Development Workflow

```bash
# 0. Make a new connector project using the workato SDK CLI
workato new

# 1. Initialise wisco
wisco init

# 2. Download an existing connector from Workato (Optional) 
wisco pull

# 3. Inspect what the connector exposes
wisco list all

# 4. Test the connection at any time
wisco exec test

# 5. Generate fixture templates for an action (or: trigger, method, pick_list)
wisco fixtures actions.get_user

# Fill in execute_input.json, then remove the sentinel comment line

# 6. Execute against live credentials
wisco exec actions.get_user

# 7. Review output
cat fixtures/actions/get_user/output_execute_input.json

# 8. Generate input/output schemas from API responses
wisco schema sample.json

# 9. Publish connector to workato
wisco push

```
---

## Commands

### `wisco init [path]`

Initialises a connector project. Run this once per project, and again whenever project settings change.

What it does:
- Detects the connector `.rb` file in the target directory
- Creates or updates `.wisco/config.json` (stores connector path, file, and Workato hostname)
- Prompts you to select your Workato data centre (US, EU, JP, SG, AU, IL)
- Copies a `.gitignore` template into the project root if one is not already present
- Copies a `Gemfile` template into the project root if one is not already present — run `bundle install` afterwards
- Creates `.github/workflows/deploy.yml` from a template (prompts before overwriting)

```bash
wisco init
wisco init ./my-connector
```

The config is stored at `.wisco/config.json` inside the connector project:

```json
{
  "connector": {
    "path": "/path/to/connector",
    "file": "connector.rb"
  },
  "workato_developer_api": {
    "hostname": "app.au.workato.com",
    "api_token": "<your token>"
  },
  "connection": "default"
}
```

---

### `wisco profile <subcommand>`

Manages named Workato connection profiles stored centrally in `~/.wisco/profiles.yaml`. Profiles let you reuse credentials across multiple connector projects — when a token rotates, update the profile once and every project that references it picks up the change automatically.

| Subcommand | Description |
|------------|-------------|
| `add [name]` | Create a new profile (prompts for hostname and API token; suggests a name from the datacenter) |
| `list` | List all profiles |
| `show <name>` | Show a profile's hostname and masked token |
| `edit <name>` | Update a profile's hostname or API token |
| `remove <name>` | Remove a profile |
| `use <name>` | Attach a profile to the current connector project |
| `extract [name]` | Save this project's inline credentials as a named profile |
| `current` | Show which profile (or inline credentials) this project is using |

```bash
wisco profile add                     # create a profile (name suggested from datacenter)
wisco profile add my-profile          # create with an explicit name
wisco profile list                    # list all profiles
wisco profile use my-profile          # attach a profile to the current project
wisco profile extract                 # migrate inline credentials to a profile
wisco profile edit my-profile         # update hostname or token
wisco profile current                 # show what this project is using
```

Profiles are stored in `~/.wisco/profiles.yaml`. Existing projects with inline credentials in `.wisco/config.json` continue to work unchanged — profile support is opt-in.

`wisco init` also accepts `--profile <name>` to attach a profile during project setup, and will offer a profile selection menu if any profiles already exist.

---

### `wisco list [subcommand] [path]`

Inspects a connector's structure without executing anything.

| Subcommand | Output |
|------------|--------|
| *(none)*   | Tree overview of top-level keys |
| `actions`  | Markdown table of all actions |
| `triggers` | Markdown table of all triggers |
| `all`      | Overview + actions table + triggers table |

```bash
wisco list
wisco list actions
wisco list triggers
wisco list all
wisco list actions --sort=title
wisco list --format=json        # machine-readable JSON
wisco list --format=yaml        # machine-readable YAML
```

Options:

| Option | Description |
|--------|-------------|
| `--sort=key\|title` | Sort the actions/triggers table |
| `--format=json\|yaml` | Output the complete connector structure as JSON or YAML. All lambda values are serialized as either `"__is_lambda__"` (most sections) or as `{ "parameters": [...] }` arrays for methods and pick_lists. All sections are sorted alphabetically by key. Intended for machine consumption (e.g., VS Code extension). Subcommand is ignored when `--format` is set. |

---

### `wisco fixtures <path> [target_dir]`

Fetches input and output field schemas from the connector and writes fixture template files. Run this before `wisco exec`.

```bash
wisco fixtures actions.get_user
wisco fixtures triggers.new_record
wisco fixtures actions               # all actions
wisco fixtures pick_lists
wisco fixtures methods
wisco fixtures actions --overwrite   # regenerate even if already edited
```

**Path forms:**

| Form | Meaning |
|------|---------|
| `section.key` | One specific item |
| `section` | All items in that section |
| `key` | Auto-detect section (error if found in multiple) |

**Valid sections:** `actions`, `triggers`, `pick_lists`, `methods`

**Files created** under `fixtures/<section>/<key>/`:

| File | Description |
|------|-------------|
| `input_fields.json` | Schema of the input fields |
| `output_fields.json` | Schema of the output fields |
| `execute_input.json` | Template input for `wisco exec` — edit this, removing the sentinel comment |
| `config_fields.json` | Created if the item has `config_fields` — fill this in first, then re-run |
| `execute_input.rb` *(with `--ruby`)* | Template Ruby script for dynamic input — see `wisco exec` below |

The `execute_input.json` file starts with a sentinel comment line. Remove it once you have filled in the values — `wisco exec` skips files that still contain the sentinel.

Options: `--overwrite`, `--ruby`, `--debug`

Pass `--ruby` to also scaffold an `execute_input.rb` template alongside the JSON one. Ruby scripts let you generate input dynamically — useful for unique IDs, timestamps, or chained lookups against the connector itself.

---

### `wisco exec <path> [target_dir]`

Executes connector items using the fixture data prepared by `wisco fixtures`.

```bash
wisco exec actions.get_user
wisco exec triggers.new_record
wisco exec pick_lists.object_types
wisco exec methods.format_date
wisco exec test                      # test the connection
wisco exec actions                   # execute all actions
```

For each ready `execute_*.json` file found in the fixture directory, wisco invokes the method using that file as input and writes the result to `output_<name>.json`. If execution fails, the error and stack trace are written to `error_<name>.txt`.

If the fixture directory for an item does not exist, `wisco exec` will automatically run `wisco fixtures` for that item before executing. For pick lists and methods with no parameters this means you can skip the manual `wisco fixtures` step entirely and run `wisco exec` directly.

#### Dynamic input via Ruby scripts
wisco also supports `execute_*.rb` fixtures whose last expression becomes the input. This lets you generate fresh values per run — unique order numbers, current timestamps, randomised test data, or chained lookups that fetch a real ID from the connector itself.

```ruby
# fixtures/actions/create_order/execute_input.rb
require 'securerandom'
{
  order_number: "ORD-#{SecureRandom.hex(4).upcase}",
  created_at:   Time.now.iso8601,
  customer_id:  call_pick_list(:active_customers).first[1]
}
```

Helpers available inside the script:

| Helper | Purpose |
|---|---|
| `call_method(:name, *args)` | Invoke a connector `methods:` entry |
| `call_pick_list(:name, *args)` | Invoke a connector `pick_lists:` entry |
| `connection` | Hash of decrypted `settings.yaml` (or `settings.yaml.enc`) for the configured connection |

Output for each `.rb` script lives in its own subdirectory (`<script_name>/input.json` + `output.json` + `error.txt` on failure) so it doesn't collide with the JSON run output. Skip a script by leaving `# WISCO_SKIP` as its first non-blank line. Scaffold a template with `wisco fixtures <path> --ruby`.

#### Options:

| Option | Default | Description |
|--------|---------|-------------|
| `--input=file.json` | — | Use a specific input file instead of all `execute_*` files |
| `--pagination` | `true` | Triggers: `true` = `.poll` (with pagination), `false` = `.poll_page` |
| `--verbose` | `false` | Enable detailed SDK logging |
| `--extended` | `true` | Auto-pass `input_fields.json`/`output_fields.json` as extended schema for actions/triggers |
| `--closure=file.json` | — | Closure data file (triggers: simulate a subsequent poll) |
| `--config-fields=file.json` | — | config_fields data file |
| `--continue=file.json` | — | Continue data file (multistep actions) |
| `--extended-input-schema=file.json` | — | Override the auto-detected extended input schema |
| `--extended-output-schema=file.json` | — | Override the auto-detected extended output schema |
| `--debug` | `false` | Print ExecCommand call details |
| `--summary` / `--no-summary` | `true` | Show output summary after each execution |
| `--summary-lines=N` | `20` | Max output lines to print in full; larger outputs show summary only |

For `--closure`, `--config-fields`, `--continue`, `--extended-input-schema`, and `--extended-output-schema`: if you supply a bare filename (e.g. `closure.json`) it is resolved relative to the item's fixture directory. A path with directory separators is used as-is.

#### Output summary

After each execution, wisco prints a summary to stdout:

- **Small outputs** (≤ `--summary-lines` lines): the full JSON is printed, followed by a type summary line.
- **Large outputs**: summary line only — e.g. `Array: 47 items — first: {"id": 1002, "name": "Order #1002", ...}` or `Hash: 12 keys — id, name, status, ...`.
- **Pick lists** (single): items are displayed as a Markdown-compatible table with `Label` and `Value` columns. When running multiple pick lists at once, only a count is shown per list.

Use `--no-summary` to suppress all summary output and revert to `Written: <file>` only.

**Testing a connection:**

```bash
wisco exec test
wisco exec test --no-verbose
```

Credentials come from `settings.yaml` in the connector directory. Output is written to `fixtures/connection/test/output_test.json`.

---

### `wisco schema <input_file> [target_dir]`

Generates a Workato schema from a JSON or CSV sample file by calling the Workato Developer API. File type is auto-detected from the extension.

```bash
wisco schema sample.json                        # Ruby output (default)
wisco schema sample.json --format=json          # raw JSON output
wisco schema sample.json --ruby_options=single_line
wisco schema sample.csv --col-sep=semicolon
wisco schema sample.json --save                 # save to sample.schema.rb
wisco schema sample.json --save=my_schema.rb    # save to a specific file
```

| Option | Default | Description |
|--------|---------|-------------|
| `--format` | `ruby` | Output format: `ruby` or `json` |
| `--ruby_options` | `multi_line` | Ruby style: `single_line` or `multi_line` |
| `--col-sep` | `comma` | CSV column separator: `comma`, `space`, `tab`, `colon`, `semicolon`, `pipe` |
| `--save[=file]` | — | Save output to file. Omit value to auto-name (e.g. `sample.json` → `sample.schema.rb`) |
| `--debug` | `false` | Show API call details |

If the input JSON is a top-level array, wisco automatically wraps it in `{"input": [...]}` (required by the Workato API) and prints an `[INFO]` message. The source file is not modified.

Requires `workato_developer_api.hostname` and `workato_developer_api.api_token` in `.wisco/config.json` (token prompted on first use).

---

### `wisco pull [target_dir]`

Downloads connector data from the Workato Developer API.

```bash
wisco pull
wisco pull --what=code
wisco pull --what=all
wisco pull --title="My Connector"
```

| Option | Default | Description |
|--------|---------|-------------|
| `--what` | `all` | Comma-separated: `all`, `code`, `logo`, `versions`, `meta` |
| `--title` | *(from connector file)* | Connector title to search for |
| `--debug` | `false` | Show API call details |

Downloaded files are saved to `.wisco/pull/` inside the target directory.

Requires `workato_developer_api.hostname` and `workato_developer_api.api_token` in `.wisco/config.json` (set by `wisco init`, token prompted on first use).

---

### `wisco status [path]`

Reports the wisco state of the current directory as a JSON payload. Intended for use by the Wisco VS Code extension. Always exits 0 — check the `initialized` field to determine project state.

```bash
wisco status
wisco status ./my-connector
```

**Output fields:**

| Field | Type | Description |
|-------|------|-------------|
| `wisco_version` | string | Installed wisco version |
| `initialized` | boolean | `true` if `.wisco/config.json` exists with a valid connector entry |
| `config_path` | string\|null | Absolute path to `.wisco/config.json` |
| `profile.name` | string\|null | Attached profile name, or `null` if using inline credentials |
| `hostname` | string\|null | Effective Workato API hostname |
| `connection` | string\|null | Named connection in use |
| `connector.path` | string\|null | Absolute path to the connector `.rb` file |
| `connector.valid` | boolean\|null | Whether the connector loaded without errors |
| `connector.title` | string\|null | Connector title from the `title:` key |
| `connector.error` | string\|null | Load error message if `valid` is `false` |
| `credentials.present` | boolean\|null | Whether `settings.yaml` or `settings.yaml.enc` exists |
| `credentials.encrypted` | boolean\|null | `true` if only the encrypted form is present |

When `initialized` is `false`, all fields except `wisco_version` are `null`.

---

### `wisco push [target_dir]`

Pushes the connector to the Workato platform and releases it.

```bash
wisco push
wisco push --title="My Connector" --notes="Fix pagination bug"
```

| Option | Default | Description |
|--------|---------|-------------|
| `--title` | *(from config or connector file)* | Connector title |
| `--notes` | *(prompted)* | Version notes |
| `--folder` | — | Workato folder ID |
| `--verbose` | `false` | Enable detailed SDK logging |
| `--debug` | `false` | Show push call details |

---

## Fixture Directory Structure

```
fixtures/
├── actions/
│   └── get_user/
│       ├── execute_input.json     ← edit this (remove sentinel line)
│       ├── input_fields.json
│       └── output_fields.json
├── triggers/
│   └── new_record/
│       ├── execute_input.json
│       ├── input_fields.json
│       └── output_fields.json
├── pick_lists/
│   └── object_types/
│       └── execute_input.json     ← only created if the pick list takes parameters
├── methods/
│   └── format_date/
│       └── execute_input.json     ← positional array of argument values
└── connection/
    └── test/
        └── output_test.json       ← written by `wisco exec test`
```