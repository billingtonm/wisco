# Wisco

Wisco is a small Ruby CLI for working with Workato connector projects.

It helps with three common tasks:

- Detecting a connector file and creating local project configuration
- Inspecting connector structure from the command line
- Running connector field and execute flows through the Workato Connector SDK CLI

The tool is designed for local development against a connector project directory and uses a per-project config file named `.wisco.json`.

## Features

- `init` discovers a connector file and writes `.wisco.json`
- `list` prints a structural overview of a connector
- `list actions` and `list triggers` render markdown-friendly tables
- `list all` combines overview, actions, and triggers output
- `exec --mode=fields` generates fixture files for input and output fields
- `exec --mode=execute` runs connector methods with prepared input files

## Requirements

- Ruby `2.7.6`
- Bundler
- The gems listed in [Gemfile](Gemfile)

Current runtime dependencies:

- `activesupport ~> 7.0.0`
- `workato-connector-sdk 1.3.19`

## Installation

Clone the repository and install dependencies:

```bash
bundle install
```

Run the CLI from the repository root:

```bash
bundle exec ruby wisco.rb --help
```

On Windows, you can also use [wisco.bat](wisco.bat).

## Quick Start

From inside a Workato connector project directory:

```bash
bundle exec ruby /path/to/wisco.rb init
bundle exec ruby /path/to/wisco.rb list
```

The `init` command creates a `.wisco.json` file in the target directory. That file stores the detected connector path and filename so later commands can load the connector consistently.

Example:

```json
{
  "connector": {
    "path": "/path/to/connector/project",
    "file": "connector.rb"
  }
}
```

## Commands

### `init [path]`

Detects a connector file and creates or updates `.wisco.json`.

If no path is provided, the current directory is used.

Examples:

```bash
bundle exec ruby wisco.rb init
bundle exec ruby wisco.rb init ./my-connector
```

### `list [path]`

Prints a tree view of the top-level connector structure.

Examples:

```bash
bundle exec ruby wisco.rb list
bundle exec ruby wisco.rb list ./my-connector
```

### `list actions [path]`

Prints actions as a markdown table.

```bash
bundle exec ruby wisco.rb list actions
```

### `list triggers [path]`

Prints triggers as a markdown table.

```bash
bundle exec ruby wisco.rb list triggers
```

### `list all [path]`

Prints the overview, actions, and triggers together.

```bash
bundle exec ruby wisco.rb list all
```

### `exec <path> [target_dir]`

Runs connector execution flows.

Accepted path forms:

- `actions.some_action`
- `triggers.some_trigger`
- `actions`
- `triggers`
- `some_action` or `some_trigger` when the key is unique across sections

#### Field mode

Use field mode to generate fixture files for a connector method:

```bash
bundle exec ruby wisco.rb exec actions.get_users --mode=fields
```

This creates files under `fixtures/<section>/<key>/`, including:

- `input_fields.json`
- `output_fields.json`
- `execute_input.json`

The generated `execute_input.json` starts with a sentinel comment so you can distinguish an untouched template from real input.

#### Execute mode

Use execute mode to run one or more prepared inputs:

```bash
bundle exec ruby wisco.rb exec actions.get_users --mode=execute
bundle exec ruby wisco.rb exec actions.get_users --mode=execute --input=execute_input.json
```

Outputs are written into the same fixture directory as:

- `output_<input>.json`
- `error_<input>.txt` when execution fails

#### Exec options

- `--mode=execute` runs the action or trigger execution path
- `--mode=fields` fetches input and output field schemas
- `--input=file.json` selects a specific execute input file
- `--overwrite=true` overwrites a generated execute input template
- `--debug` prints execution details

## Configuration

Wisco uses `.wisco.json` in the target connector directory.

At minimum, it stores:

- `connector.path`
- `connector.file`

It may also contain connection data used during execution.

## Typical Workflow

```bash
bundle exec ruby wisco.rb init
bundle exec ruby wisco.rb list all
bundle exec ruby wisco.rb exec actions.get_users --mode=fields
# edit fixtures/actions/get_users/execute_input.json
bundle exec ruby wisco.rb exec actions.get_users --mode=execute
```

## Project Structure

```text
wisco.rb
wisco.bat
lib/
  config.rb
  connector.rb
  commands/
    init.rb
    list.rb
    exec.rb
helpers/
```

## Development Notes

- The project uses `Workato::CLI::ExecCommand` from the Workato Connector SDK.
- Connector files are evaluated locally to discover and load connector definitions.
- `connector.rb` is preferred during detection, but other `.rb` files in the target directory are also considered.

