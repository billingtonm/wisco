# 10. Connection Settings — `wisco settings`

## 10.1 Overview

The Workato Connector SDK stores the credentials used to connect to the *target service* (e.g. Shopify, Salesforce) in a **settings file** in the connector project directory:

- `settings.yaml` — plaintext, or
- `settings.yaml.enc` — encrypted (decrypted with a master key held in the `WORKATO_CONNECTOR_MASTER_KEY` environment variable or a `master.key` file).

A single settings file can hold **one** connection set (flat top-level keys) or **multiple** named connection sets (each nested under a connection-name key). See [wisco-3-exec.md] for how the active set is selected at execution time via the `connection` key in `.wisco/config.json`.

Today, working with this file means memorising the `workato edit` command, hand-editing YAML, and knowing the exact field names the connector expects. **`wisco settings`** makes this ergonomic:

- inspect which connection sets exist,
- switch the project's active connection set,
- scaffold a new connection set using the field names declared by the connector,
- inspect the connection fields the connector defines.

wisco reads the field definitions straight from the connector's `connection.fields` array, so the user never has to look up field names manually.

---

## 10.2 The Settings File

### Location

The settings file lives in the connector directory (`connector.path` from `.wisco/config.json`), alongside the connector `.rb` file:

```
<connector.path>/settings.yaml        # plaintext
<connector.path>/settings.yaml.enc    # encrypted
<connector.path>/master.key           # key for the encrypted form (git-ignored)
```

wisco **auto-detects** the form: if `settings.yaml.enc` exists it is treated as encrypted; otherwise `settings.yaml` is treated as plaintext. If neither exists, the file is created on first `add` (see [§10.4](#104-encryption-handling)).

### Structure — single vs multiple connections

There is **no structural "default"** and no type flag inside the file. The distinction is purely conventional:

**Single connection (flat):** top-level keys are the connection field names directly.
```yaml
shop_name: acme
client_id: abc123
client_secret: s3cr3t
site_reference: ''
```

**Multiple connections (nested):** top-level keys are connection *names*, each mapping to a field hash.
```yaml
production:
  shop_name: acme
  client_id: abc123
  client_secret: s3cr3t
sandbox:
  shop_name: acme-dev
  client_id: xyz789
  client_secret: t3st
```

### How wisco decides which shape a file is in

wisco inspects the top-level values:

- If **every** top-level value is a scalar (string/number/bool) → **flat single connection**.
- If **every** top-level value is a Hash → **nested multiple connections**.
- A mixed file (some scalars, some hashes) is treated as **ambiguous**; wisco prints a warning and treats it as nested, ignoring the stray scalar keys for listing purposes.

An empty or missing file is treated as "no connection sets defined".

---

## 10.3 Project Config Integration

`.wisco/config.json` selects the active connection set via the top-level `connection` key:

```json
{
  "connector": { "path": "/path/to/connector", "file": "connector.rb" },
  "connection": "production"
}
```

At execution time wisco passes this value to the SDK as the connection `name`, selecting the matching nested set. When `connection` is absent, the SDK reads the file as a flat single connection.

`wisco settings set <connection>` writes this key; `wisco settings current` reads it.

---

## 10.4 Encryption handling

wisco reads and writes the settings file **programmatically** via the SDK's `Workato::Connector::Sdk::Settings` class — it never shells out to `workato edit` and never requires `$EDITOR`.

- **Reading** (`list`, `show`, `current`): auto-detects encrypted vs plaintext. Decrypting an encrypted file requires the master key.
- **Writing** (`add`): merges the new set into the existing file, preserving other sets.

**Master key resolution** (encrypted files only), in priority order:

1. `WORKATO_CONNECTOR_MASTER_KEY` environment variable.
2. `master.key` file in the connector directory.

If an encrypted read/write is required but no master key is found, wisco exits with:

```
Error: settings.yaml.enc is encrypted but no master key was found.
       Set WORKATO_CONNECTOR_MASTER_KEY or provide a master.key file in <connector.path>.
```

**When no settings file exists yet**, `add` creates a **plaintext** `settings.yaml`. (Creating an encrypted file / generating a master key is out of scope for this version — a user who wants encryption can run `workato edit` once to establish `settings.yaml.enc` + `master.key`, after which `wisco settings add` will write to the encrypted form.)

---

## 10.5 Commands

All settings management is handled under the `wisco settings` subcommand. Every subcommand requires a valid `.wisco/config.json` (run `wisco init` first) and resolves the connector directory from `connector.path`.

### `wisco settings list [--format=json]`

Lists the connection sets defined in the settings file.

**Nested (multiple sets):** lists each name, marking the one the project is currently pointed at (`connection` in `config.json`) with `*`:
```
Connection sets (settings.yaml.enc):

  * production
    sandbox

Active connection (from .wisco/config.json): production
```

**Flat (single set):**
```
settings.yaml contains a single, unnamed connection set.
No named connection sets are defined. Use 'wisco settings add <name>' to create named sets.
```

**None / empty:**
```
No settings file found in <connector.path>.
Run 'wisco settings add <name>' to create one, or 'workato edit' to create an encrypted file.
```

**Machine-readable (`--format=json`):** emits a JSON array of the connection set names for tooling (e.g. the VS Code extension). No decorative lines, stdout only.

```json
["production", "sandbox"]
```

- A **flat** single-connection file has no named sets → emits `[]`.
- A **none/empty/missing** file → emits `[]`.
- Reading an encrypted file still requires the master key ([§10.4](#104-encryption-handling)); if it is missing, the master-key error is emitted to stderr and wisco exits non-zero (the JSON array is not printed).

---

### `wisco settings set <connection>`

Sets the project's active connection set by writing `"connection": "<connection>"` into `.wisco/config.json`.

- Reads the settings file and **validates** that `<connection>` exists as a named set.
- If it does **not** exist, prints a warning listing the available names but still writes the value (so the workflow isn't blocked when the set is about to be created):

```
Warning: "staging" is not currently defined in settings.yaml.enc.
         Defined sets: production, sandbox
         Config updated anyway. Run 'wisco settings add staging' to create it.
```

- On success:
```
Active connection set to "sandbox" in .wisco/config.json.
```

---

### `wisco settings add <connection>`

Scaffolds a **new, named** connection set whose keys come from the connector's `connection.fields`.

**Field source:** wisco loads the connector via `Wisco::Connector.load_connector_from_config` and reads `connection.fields`. Each entry's `name` becomes a key in the new set. Values are scaffolded as **empty strings** — the user fills them in afterwards (via `workato edit`, or by editing `settings.yaml` directly when plaintext).

Given the Shopify example connector, `add production` scaffolds:
```yaml
production:
  shop_name: ''
  client_id: ''
  client_secret: ''
  site_reference: ''
```

**Structure handling — nested, with flat migration:**

`add` always writes a **nested** (named) set. Before writing, it inspects the existing file:

- **File is already nested** → the new set is merged in alongside the others.
- **File is flat (existing single connection)** → wisco offers to migrate the existing flat set into a named set first, so the file becomes consistently nested:
  ```
  settings.yaml currently holds a single unnamed connection set.
  Adding a named set requires converting the file to the named (nested) format.
  Enter a name for the existing connection set (or press Enter to skip): production
  ```
  - A name entered → the existing flat keys are moved under that name, then the new `<connection>` set is added.
  - Skipped (blank) → wisco aborts with a note that mixing flat and named sets is unsupported.
- **File is empty / missing** → a plaintext `settings.yaml` is created containing just the new nested set.

**Duplicate guard:** if `<connection>` already exists as a named set, `add` errors (it will not overwrite existing values):
```
Error: Connection set "production" already exists in settings.yaml.enc.
       Use 'wisco settings show production' to view it, or edit it with 'workato edit'.
```

**Encryption:** the new set is written to whichever form the file is in (encrypted if `settings.yaml.enc`, else plaintext), honouring the master-key rules in [§10.4](#104-encryption-handling).

**On success:**
```
Added connection set "production" to settings.yaml.enc with 4 blank field(s):
  shop_name, client_id, client_secret, site_reference
Fill in the values with 'workato edit', then run 'wisco settings set production'.
```

---

### `wisco settings show [<connection>]`

Displays the stored field values for one connection set. Fields whose connector definition has `control_type: 'password'` are masked (`****` + last 4 chars); all others are shown in full.

```
Connection set: production   (settings.yaml.enc)

  shop_name       acme
  client_id       abc123
  client_secret   ****cr3t
  site_reference  (blank)
```

**The `<connection>` argument is optional.** Resolution depends on the file shape:

- **Flat (single set):** `<connection>` may be omitted — `show` displays the single unnamed set. A header without a name is used:
  ```
  Connection set: (single/unnamed)   (settings.yaml)
  ```
  If `<connection>` **is** supplied for a flat file, it errors (there are no named sets to select).
- **Nested (multiple sets):**
  - `<connection>` supplied → shows that set; errors if the name is not present, listing the available names.
  - `<connection>` **omitted** → wisco cannot guess which set is meant, so it prints a warning and lists the available names without showing values:
    ```
    Warning: This settings file has multiple connection sets; specify which one to show.
             Defined sets: production, sandbox
    ```
- **None / empty file:** errors that there is nothing to show.

Masking requires the connector's `connection.fields` to identify password fields; if the connector cannot be loaded, wisco warns and shows all values unmasked.

**Machine-readable (`--format=json`):** emits the connector's `connection.fields` array (same shape as `wisco settings fields --format=json`), with each field augmented by a `value` key holding the current stored value for that field — `null` when the field is unset or blank. Output is driven by `connection.fields`, so stored keys not declared by the connector are omitted. Values are **unmasked** (this output is for tooling, not display).

```json
[
  {
    "name": "shop_name",
    "label": "Shop name",
    "control_type": "subdomain",
    "url": ".myshopify.com",
    "optional": false,
    "hint": "Enter your Shopify store subdomain...",
    "value": "acme"
  },
  {
    "name": "client_secret",
    "label": "API secret key",
    "control_type": "password",
    "optional": false,
    "hint": "Found alongside your API key...",
    "value": "s3cr3t"
  }
]
```

The set is resolved exactly as in the human path: a flat file needs no `<connection>`; a nested file requires one (the multiple-sets warning still applies when it is omitted). If the connector cannot be loaded, `show --format=json` exits with the load error (it cannot produce the fields array).

---

### `wisco settings current`

Shows which connection set the current project points at (the `connection` key in `.wisco/config.json`) and whether it exists in the settings file.

**Configured and present:**
```
This project uses connection set: production
  Defined in: settings.yaml.enc  ✓
```

**Configured but missing from settings:**
```
This project uses connection set: production
  Not found in settings.yaml.enc. Run 'wisco settings add production' to create it.
```

**Not configured (flat / single connection):**
```
This project has no named connection selected (config.json has no "connection" key).
The connector will use the single connection set in settings.yaml.
```

---

### `wisco settings fields [--format=json]`

Reads `connection.fields` from the connector file and lists the fields the connector expects for a connection. Purely informational — reads nothing from the settings file.

**Default (human-readable table):**
```
Connection fields (from connector.rb):

  Name            Label              Type        Required
  shop_name       Shop name          subdomain   yes
  client_id       API key / Client…  (default)   yes
  client_secret   API secret key     password    yes
  site_reference  Site reference     (default)   no
```

Columns are drawn from each field's `name`, `label`, `control_type` (shown as `(default)` when absent), and `optional` (inverted → `Required`).

**Machine-readable (`--format=json`):** emits the `connection.fields` array as JSON, with symbol keys stringified, for tooling (e.g. the VS Code extension):
```json
[
  {
    "name": "shop_name",
    "label": "Shop name",
    "control_type": "subdomain",
    "url": ".myshopify.com",
    "optional": false,
    "hint": "Enter your Shopify store subdomain..."
  },
  {
    "name": "client_id",
    "label": "API key / Client ID",
    "optional": false,
    "hint": "Found in your Shopify Partner Dashboard..."
  }
]
```

- If the connector defines no `connection.fields`, prints `Connector defines no connection fields.` (human) or `[]` (JSON).
- If the connector cannot be loaded, exits with the load error (unchanged from other commands).

---

## 10.6 Implementation notes

### New files

| File | Purpose |
|------|---------|
| `lib/wisco/commands/settings.rb` | Thor subcommand class `Wisco::Commands::Settings` — `list`, `set`, `add`, `show`, `current`, `fields`. Mirrors `lib/wisco/commands/profile.rb`. |
| `lib/wisco/settings_store.rb` | Model layer `Wisco::SettingsStore` — wraps `Workato::Connector::Sdk::Settings` for read/write, master-key resolution, and flat-vs-nested detection. |

### Reading connection fields

```ruby
connector = Wisco::Connector.load_connector_from_config(target_dir)  # returns Hash, symbol keys
fields    = connector.dig(:connection, :fields) || []                # array of field Hashes
```
Wrap in `rescue` — a broken connector `raise`s rather than returning (same convention as [wisco-9-status.md]).

### Reading the settings file

```ruby
# Auto-detect encrypted vs plaintext, resolving paths against the connector dir:
Workato::Connector::Sdk::Settings.from_default_file            # whole file (all sets)
# or explicitly:
Workato::Connector::Sdk::Settings.from_encrypted_file(enc_path, key_path)
Workato::Connector::Sdk::Settings.from_file(plain_path)
```
Because the SDK resolves default paths against the current working directory, `SettingsStore` should either `Dir.chdir(connector_path)` around the call or pass explicit absolute paths for `path` and `key_path`.

### Writing a connection set (no editor)

```ruby
Workato::Connector::Sdk::Settings.new(
  path:      settings_path,       # settings.yaml.enc or settings.yaml
  encrypted: encrypted?,          # MUST be set explicitly; #update does not auto-detect
  name:      connection_name,     # nested set name
  key_path:  master_key_path      # only used when encrypted
).update(field_hash)              # shallow-merges under `name`
```

`#update` **replaces** keys on merge, so `add` must guard against overwriting an existing set (duplicate check) before calling it.

### Master key resolution

Check `ENV['WORKATO_CONNECTOR_MASTER_KEY']` first, then `File.exist?(File.join(connector_path, 'master.key'))`. If encrypted work is required and neither is present, emit the [§10.4](#104-encryption-handling) error and `exit 1`.

### CLI declaration (`lib/wisco.rb`)

Register a subcommand router next to `profile`:

```ruby
require_relative 'wisco/commands/settings'

desc 'settings SUBCOMMAND ...ARGS', 'Manage the connector settings file (credential sets)'
long_desc <<~DESC
  Subcommands:
    list                 List connection sets (--format=json for a JSON array of names)
    set <connection>     Set the project's active connection set
    add <connection>     Scaffold a new connection set from connector.connection.fields
    show [<connection>]  Show a connection set's field values (passwords masked)
    current              Show which connection set the project points at
    fields               List the connector's connection fields (--format=json for JSON)
DESC
subcommand 'settings', Wisco::Commands::Settings
```

The `list`, `fields`, and `show` subcommands each declare `option :format, type: :string, enum: %w[json]` above their `def`. `show` also takes an optional positional argument: `def show(connection = nil)`.

### Terminal output conventions

Follow the existing split: normal output and prompts → `puts` / `print` (stdout); warnings and errors → `Wisco::TerminalOutput.emit_warning` / `emit_error` (stderr). `fields --format=json` and any machine-readable output go to stdout only, with no decorative lines.

---

## 10.7 Backwards Compatibility

- Existing projects are unaffected: the settings file format is unchanged, and the `connection` key in `config.json` already exists and is already honoured by `wisco exec` / `wisco fixtures`.
- `wisco settings` is purely additive — no migration is forced. Flat single-connection files keep working; migration to nested format only happens when the user explicitly runs `add` and opts in.

---

## 10.8 Summary of New Files and Changes

| File | Change |
|------|--------|
| `lib/wisco/commands/settings.rb` | New — all `wisco settings` subcommand logic (list, set, add, show, current, fields) |
| `lib/wisco/settings_store.rb` | New — read/write wrapper over the SDK `Settings` class, master-key resolution, flat/nested detection |
| `lib/wisco.rb` | Register `settings` command and subcommands |
| `<connector.path>/settings.yaml`(`.enc`) | May be created/updated by `wisco settings add` |
| `.wisco/config.json` | `connection` key written by `wisco settings set` (key already consumed elsewhere) |
| `README.md` | Add a `wisco settings` section |
