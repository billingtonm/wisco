# 1. Getting Started — `wisco init`

## 1.1 Overview

`wisco init [path]`

Run this in a Workato connector project folder. If no path is supplied, the current directory is used.

`init` is safe to re-run — it will not overwrite files the user has already edited, and will prompt before replacing generated files like `deploy.yml`.

---

## 1.2 Connector Detection

`init` searches the target directory for a valid Workato connector file. The search order is:

1. Look for `connector.rb` first.
2. If not found, scan for any other `*.rb` file in the directory.

Each candidate is validated by calling `eval` on its contents. A valid connector file evaluates to a Ruby hash that contains a `title` key. If no valid file is found, an error is raised and the command exits.

---

## 1.3 Config Directory and File

Once a connector is detected, `init` creates the `.wisco/` directory at the project root (if it does not already exist) and writes a `config.json` file inside it:

```
<project_root>/
└── .wisco/
    └── config.json
```

> Note: The config file is `.wisco/config.json`, **not** `.wisco.json`.

The config file stores the connector location, the selected Workato hostname, and (once set) the API token and connection name:

```json
{
  "connector": {
    "path": "/path/to/connector/project",
    "file": "connector.rb"
  },
  "workato_developer_api": {
    "hostname": "app.au.workato.com",
    "api_token": "<set on first push/pull>"
  },
  "connection": "default"
}
```

If a `config.json` already exists, `init` updates the `connector.path` and `connector.file` keys and merges any prompted values, preserving all other keys.

---

## 1.4 Hostname Prompt

After detecting the connector, `init` prompts the user to select their Workato data centre. The available hostnames are:

| # | Hostname | Region |
|---|----------|--------|
| 1 | `www.workato.com` | US Data Center |
| 2 | `app.eu.workato.com` | EU Data Center |
| 3 | `app.jp.workato.com` | JP Data Center |
| 4 | `app.sg.workato.com` | SG Data Center |
| 5 | `app.au.workato.com` | AU Data Center |
| 6 | `app.il.workato.com` | IL Data Center |

If a hostname is already set in `config.json`, the current value is shown and the user is asked whether to keep it. Entering `n` re-shows the numbered list.

The selected hostname is stored as `workato_developer_api.hostname` in `config.json` and is used by `wisco push` and `wisco pull`.

---

## 1.5 File Deployment

After writing the config, `init` checks for the presence of several standard project files and deploys them from built-in templates if they are missing.

### `.gitignore`

- **If `.gitignore` does not exist:** copies `lib/wisco/assets/.gitignore` to the project root.
- **If `.gitignore` exists but does not contain `.wisco/`:** appends the entry `.wisco/` to the existing file.
- **If `.gitignore` exists and already contains `.wisco/`:** no changes made.

The asset `.gitignore` includes entries for `.wisco/`, `master.key`, fixture error files, and local working data.

### `Gemfile`

- **If `Gemfile` does not exist:** copies `lib/wisco/assets/Gemfile` to the project root and prints an `[INFO]` message advising the user to run `bundle install`.
- **If `Gemfile` already exists:** no changes made.

The asset `Gemfile` includes the `workato-connector-sdk` gem plus common testing dependencies (`rspec`, `vcr`, `webmock`, `timecop`, `byebug`).

> `Gemfile.lock` is intentionally not generated — it is platform-specific and must be produced by `bundle install` in the user's own environment.

### `.github/workflows/deploy.yml`

- **If the file does not exist:** rendered from the ERB template `lib/wisco/assets/.github/workflows/deploy.yml.erb` using the connector filename and Workato base URL, then written to `.github/workflows/deploy.yml`. The `.github/workflows/` directory is created if needed.
- **If the file already exists:** the user is prompted `Overwrite? (y/n)`. Entering `n` skips the file.

Template variables used during rendering:

| Variable | Source |
|----------|--------|
| `connector_name` | Connector filename (e.g. `connector.rb`) |
| `workato_base_url` | `https://<hostname>` from the selected hostname |

---

## 1.6 Summary of Steps

In order, `wisco init`:

1. Validates the target directory exists
2. Detects the connector file
3. Creates `.wisco/` directory
4. Loads existing `config.json` (or starts from empty)
5. Updates `connector.path` and `connector.file`
6. Prompts for (or confirms) the Workato hostname
7. Saves `config.json`
8. Deploys `.gitignore`
9. Deploys `Gemfile`
10. Deploys `.github/workflows/deploy.yml`
