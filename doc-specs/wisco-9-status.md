# 9. wisco status

## Purpose

`wisco status` returns a machine-readable JSON payload describing the state of wisco in the current working directory. It is intended to be called by the Wisco VS Code extension to determine availability and configuration before offering any features.

## Command

```bash
wisco status [PATH]
```

`PATH` defaults to the current directory (same convention as all other wisco commands).

## Behaviour

- **Always exits 0**, regardless of initialisation state or errors. The caller reads the JSON to determine state; it never needs to catch exit codes.
- Output is always valid JSON written to stdout.
- No output is written to stderr unless a truly unexpected Ruby exception occurs.

---

## Output structure

### When initialised

```json
{
  "wisco_version": "0.4.1",
  "initialized": true,
  "config_path": "/home/user/projects/my-connector/.wisco/config.json",
  "profile": {
    "name": "au-prod"
  },
  "hostname": "app.au.workato.com",
  "connection": "default",
  "connector": {
    "path": "/home/user/projects/my-connector/connector.rb",
    "valid": true,
    "title": "My Connector",
    "error": null
  },
  "credentials": {
    "present": true,
    "encrypted": false
  }
}
```

### When not initialised

```json
{
  "wisco_version": "0.4.1",
  "initialized": false,
  "config_path": null,
  "profile": null,
  "hostname": null,
  "connection": null,
  "connector": null,
  "credentials": null
}
```

### When initialised but connector has errors

```json
{
  "wisco_version": "0.4.1",
  "initialized": true,
  "config_path": "/home/user/projects/my-connector/.wisco/config.json",
  "profile": null,
  "hostname": "app.au.workato.com",
  "connection": "default",
  "connector": {
    "path": "/home/user/projects/my-connector/connector.rb",
    "valid": false,
    "title": null,
    "error": "undefined method 'foo' for nil:NilClass"
  },
  "credentials": {
    "present": true,
    "encrypted": false
  }
}
```

---

## Fields

### `wisco_version`

String. The installed wisco gem version (e.g. `"0.4.1"`). Always present. Allows the extension to gate features on capability.

### `initialized`

Boolean. `true` if `.wisco/config.json` exists and contains a valid connector path and file. `false` otherwise. When `false`, all remaining fields (except `wisco_version`) are `null`.

### `config_path`

String or null. Absolute path to `.wisco/config.json`. Provided so the extension can read additional settings directly from the config file without requiring wisco to expose every field.

### `profile`

Object or null.

- `name` — string or null. Name of the attached profile (from `~/.wisco/profiles.yaml`). `null` if using inline credentials in the config file.

### `hostname`

String or null. The effective Workato API hostname (e.g. `app.au.workato.com`). Resolved from the profile if one is attached, otherwise from `workato_developer_api.hostname` in the config. `null` if not configured.

### `connection`

String or null. The named connection in use (e.g. `"default"`, `"staging"`). From `connection` in the config.

### `connector`

Object or null.

- `path` — string. Absolute path to the connector `.rb` file.
- `valid` — boolean. `true` if the file was found and loaded (eval'd) without errors.
- `title` — string or null. The connector's `title:` key. `null` if the connector could not be loaded.
- `error` — string or null. The error message if `valid` is `false`, otherwise `null`.

### `credentials`

Object or null.

- `present` — boolean. `true` if `settings.yaml` or `settings.yaml.enc` exists in the connector directory.
- `encrypted` — boolean. `true` if only `settings.yaml.enc` is present (no plaintext `settings.yaml`). `false` if plaintext settings exist (regardless of whether an encrypted copy also exists).

---

## Implementation notes

### Config loading

Use `Wisco::Config.load_config(config_path)` — same as all other commands.

### Connector loading

Wrap `Wisco::Connector.load_connector_from_config(target_dir)` in a `rescue` to catch eval errors. Do not call `exit 1` on failure — capture the error message and set `valid: false`.

### Profile resolution

Use `Wisco::Profile` to look up the attached profile name and resolve the hostname. If no profile is attached, fall back to `workato_developer_api.hostname` from the config.

### Output

Use `JSON.pretty_generate` for human-readable output (consistent with `wisco list --format=json`). The extension should parse it regardless of formatting.

---

## CLI declaration (`lib/wisco.rb`)

```ruby
desc 'status [PATH]', 'Report wisco project status as JSON (for tooling)'
def status(path = nil)
  Wisco::Commands::Status.run(path || Dir.pwd)
end
```

No options. The command is intentionally simple — the extension reads the JSON and makes its own decisions.

---

## New file

`lib/wisco/commands/status.rb` — follows the same module pattern as other commands:

```ruby
module Wisco
  module Commands
    module Status
      module_function

      def run(target_dir)
        # ...
      end
    end
  end
end
```
