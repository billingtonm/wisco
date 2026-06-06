# 8. Connection Profiles — `wisco profile`

## 8.1 Overview

wisco commands that interact with the Workato API (`push`, `pull`, `schema`) require a hostname and API token. Currently these are stored per-project in `.wisco/config.json`.

When a user works across multiple connector projects that share the same Workato instance, they must configure the same credentials repeatedly. If a token is rotated, every project must be updated individually.

**Connection profiles** solve this by storing named credential sets in a single central file (`~/.wisco/profiles.yaml`). A connector project can reference a profile by name; wisco resolves the credentials at runtime from the central file.

---

## 8.2 Profiles File

### Location

```
~/.wisco/profiles.yaml
```

This file is created automatically when the first profile is added via `wisco profile add`. It is plain YAML and can also be edited directly in a text editor.

### Format

```yaml
workato_developer_api:
  my-au-profile:
    hostname: app.au.workato.com
    api_token: xxxxxxxxxxxxxxxx
  my-us-profile:
    hostname: app.workato.com
    api_token: yyyyyyyyyyyyyyyy
```

- The top-level key `workato_developer_api` namespaces Workato Developer API profiles. This mirrors the `workato_developer_api` key in `config.json` and allows other profile types to be added in future.
- Each profile is identified by a name (e.g. `my-au-profile`). Names can contain letters, numbers, hyphens, and underscores.
- There is no designated default profile. wisco always prompts the user to select a profile explicitly.

---

## 8.3 Project Config Integration

When a project uses a profile, `config.json` stores a `profile` key under `workato_developer_api` instead of (or in place of) inline credentials:

**Profile reference (new style):**
```json
{
  "workato_developer_api": {
    "profile": "my-au-profile"
  }
}
```

**Inline credentials (legacy style — continues to work):**
```json
{
  "workato_developer_api": {
    "hostname": "app.au.workato.com",
    "api_token": "<api_token>"
  }
}
```

### Credential resolution

When a wisco command needs the hostname and api_token, the resolution order is:

1. If `workato_developer_api.profile` is present in `config.json` → look up the named profile in `~/.wisco/profiles.yaml` and use its `hostname` and `api_token`.
2. If `workato_developer_api.hostname` and `workato_developer_api.api_token` are present → use them directly (legacy inline behaviour, unchanged).
3. If neither is present → prompt the user (existing behaviour for unconfigured projects).

### Conflict: both profile and inline credentials present

If `config.json` contains **both** a `profile` key and inline `hostname`/`api_token` under `workato_developer_api`, wisco treats this as a misconfiguration. It will:

1. Print a warning explaining the conflict.
2. Ask the user which to keep:
   - **Keep profile** — removes the inline `hostname` and `api_token` from `config.json`
   - **Keep inline credentials** — removes the `profile` key from `config.json`
3. Save the resolved `config.json` and continue.

### Missing profile

If `config.json` references a profile name that does not exist in `~/.wisco/profiles.yaml`, wisco exits with an error:

```
Error: Profile "my-au-profile" not found in ~/.wisco/profiles.yaml.
       Run 'wisco profile list' to see available profiles.
```

---

## 8.4 Commands

All profile management is handled under the `wisco profile` subcommand.

### `wisco profile add [<name>] --hostname=<domain> --api_token=<xxxxx>`

Creates a new profile. Unless options (`--hostname`, `--api_token`) are provided, it prompts interactively for:

- **Hostname** — presents the standard Workato datacenter list (same as `wisco init`)
- **API token** — input is masked

**Name suggestion:** If `<name>` is omitted, wisco suggests a name derived from the selected datacenter (e.g. selecting `app.au.workato.com` suggests `au`). The user can accept the suggestion or enter a custom name.

| Hostname | Suggested name |
|---|---|
| `www.workato.com` | `us` |
| `app.eu.workato.com` | `eu` |
| `app.jp.workato.com` | `jp` |
| `app.sg.workato.com` | `sg` |
| `app.au.workato.com` | `au` |
| `app.il.workato.com` | `il` |

Saves the new profile to `~/.wisco/profiles.yaml`. Creates the file (and `~/.wisco/` directory) if they do not exist.

Errors if a profile with the given name already exists.

---

### `wisco profile list`

Lists all profiles defined in `~/.wisco/profiles.yaml`.

Example output:
```
Profiles (from ~/.wisco/profiles.yaml):

  my-au-profile    app.au.workato.com
  my-us-profile    app.workato.com
```

Prints a message if no profiles have been created yet.

---

### `wisco profile show <name>`

Prints the details of a single profile. The API token is masked (shows last 4 characters preceded by `****`).

Example output:
```
Profile: my-au-profile
  hostname:  app.au.workato.com
  api_token: ****xxxx
```

---

### `wisco profile edit <name>`

Re-prompts for the hostname and API token of an existing profile. Useful when a token is rotated — update the profile once and all connector projects that reference it are updated automatically.

Shows the current values as defaults; the user can press Enter to keep them.

---

### `wisco profile remove <name>`

Removes a profile from `~/.wisco/profiles.yaml`.

Prompts for confirmation before deleting:
```
Remove profile "my-au-profile"? (y/n)
```

Does **not** check whether any connector projects reference this profile. If a project references a removed profile, wisco will error when the project is next used (see *Missing profile* above).

---

### `wisco profile use <name>`

Attaches an existing profile to the current connector project (updates `.wisco/config.json`).

If the project already has inline credentials (`hostname` and/or `api_token`) in `config.json`, prompts:
```
This project has inline credentials configured.
Replace with a reference to profile "my-au-profile"? (y/n)
```

- **y** — removes inline `hostname` and `api_token`, sets `profile: my-au-profile` under `workato_developer_api`.
- **n** — aborts with no changes.

Errors if the named profile does not exist in `~/.wisco/profiles.yaml`.

---

### `wisco profile extract [<name>]`

Extracts the inline credentials from the current connector project's `config.json`, saves them as a named profile in `~/.wisco/profiles.yaml`, and replaces the inline credentials with a profile reference.

**Name suggestion:** If `<name>` is omitted, wisco suggests a name derived from the project's configured hostname using the same datacenter lookup as `wisco profile add`. The user can accept or enter a custom name.

**Deduplication:** Before creating a new profile, wisco checks whether any existing profile in `profiles.yaml` has the same `hostname` and `api_token`. If a match is found:

```
A profile with these credentials already exists: au (app.au.workato.com)
Reference existing profile instead of creating a new one? (y/n)
```

- **y** — skips creating a new profile; updates `config.json` to reference the existing profile.
- **n** — proceeds to prompt for a new profile name and creates the duplicate.

**Full flow (no duplicate found):**

1. Reads `hostname` and `api_token` from `workato_developer_api` in `config.json`.
2. Errors if the project has no inline credentials to extract.
3. Suggests a profile name; user confirms or enters a custom name.
4. Writes the new profile to `~/.wisco/profiles.yaml`.
5. Updates `config.json`: removes inline `hostname` and `api_token`, sets `profile: <name>`.
6. Confirms:

```
Profile "au" created in ~/.wisco/profiles.yaml.
Project config updated to reference profile "au".
```

---

### `wisco profile current`

Displays which profile (if any) the current connector project is using.

Example output (profile in use):
```
This project uses profile: my-au-profile
  hostname:  app.au.workato.com
  api_token: ****xxxx
```

Example output (inline credentials):
```
This project uses inline credentials (no profile).
  hostname:  app.au.workato.com
  api_token: ****xxxx
```

Example output (not configured):
```
This project has no Workato API credentials configured.
Run 'wisco init' or 'wisco profile use <name>' to configure.
```

---

## 8.5 Changes to `wisco init`

### `--profile` flag

```
wisco init [path] [--profile <name>]
```

If `--profile <name>` is provided, skips the hostname prompt and attaches the named profile instead. Errors if the profile does not exist.

### Profile prompt during init (no flag)

If `~/.wisco/profiles.yaml` exists and contains at least one profile, the hostname step is replaced with:

```
Workato API credentials
  1. my-au-profile    (app.au.workato.com)
  2. my-us-profile    (app.workato.com)
  3. Enter credentials manually

Select an option:
```

- Selecting a profile sets `workato_developer_api.profile` in `config.json`.
- Selecting "Enter credentials manually" proceeds with the existing hostname + token prompts and stores inline credentials (no profile reference).

If no profiles exist, `wisco init` behaves as it does today (hostname list → api_token prompt).

---

## 8.6 Security

The profiles file is plain YAML stored at `~/.wisco/profiles.yaml`. It is outside any connector project directory and will not be committed to git by default.

wisco does not enforce file permissions on `profiles.yaml`, but the `~/.wisco/` directory should be readable only by the current user (standard home directory permissions apply on most systems).

Encryption is not implemented. The threat model is the same as the existing per-project `config.json`: credentials are protected by file system access controls, not by cryptography.

---

## 8.7 Backwards Compatibility

- All existing projects with inline `hostname` and `api_token` in `config.json` continue to work without modification.
- Profile support is entirely opt-in.
- No migration is performed automatically. Users can optionally migrate a project using `wisco profile extract` (creates a profile from inline credentials) or `wisco profile use <name>` (attaches an existing profile).

---

## 8.8 Summary of New Files and Changes

| File | Change |
|------|--------|
| `~/.wisco/profiles.yaml` | New — created on first `wisco profile add` |
| `.wisco/config.json` | May gain a `workato_developer_api.profile` key (opt-in) |
| `lib/wisco/commands/profile.rb` | New — all `wisco profile` subcommand logic (add, list, show, edit, remove, use, extract, current) |
| `lib/wisco/profile.rb` | New — read/write helpers for `profiles.yaml` |
| `lib/wisco.rb` | Register `profile` command and subcommands |
| `lib/wisco/config.rb` | Update credential resolution to check for `profile` key |
| `lib/wisco/commands/init.rb` | Add `--profile` flag; add profile selection to hostname step |
