# Development notes

## Overview
- Project is written in Ruby and exposes a Thor-based CLI under `Wisco::CLI`.
- The Workato SDK runtime is only needed by the commands that execute connector methods:
  - `exec`
  - `fixtures`
- Commands that inspect local files only (`init`, `list`, `version`) stay within Wisco's own modules.
- The root `wisco.rb` file is only a thin local wrapper. The actual CLI definitions, constants, and command wiring live in `lib/wisco.rb`.


## Structure
Current code layout:

```
bin/wisco                  # gem-installed executable; requires `wisco` and starts the CLI
wisco.rb                   # local development wrapper; prepends ./lib to LOAD_PATH and starts the CLI
lib/wisco.rb               # top-level CLI definition, constants, Thor command declarations
lib/wisco/
  version.rb               # Wisco::VERSION
  config.rb                # Wisco::Config — load/save the project config JSON
  connector.rb             # Wisco::Connector — detect and eval connector files
  path_utils.rb            # Wisco::PathUtils — parse actions/triggers path arguments
  commands/
    init.rb                # Wisco::Commands::Init.run(target_dir)
    list.rb                # Wisco::Commands::List.run(subcommand, target_dir, sort:)
    exec.rb                # Wisco::Commands::Exec.run(path_arg, target_dir, ...)
    fixtures.rb            # Wisco::Commands::Fixtures.run(path_arg, target_dir, ...)
```

Command responsibilities:

- `init` detects a connector file in the target directory and writes `.wisco.json`.
- `list` loads the configured connector and renders either a tree or markdown tables.
- `exec` runs `Workato::CLI::ExecCommand` against prepared fixture inputs.
- `fixtures` calls `input_fields` and `output_fields`, then generates fixture templates.

## Workato SDK CLI requirements

The Workato-specific requires are intentionally isolated to the command modules that
need them:

```
require 'workato/connector/sdk'
require 'workato/cli/exec_command'
```

Those requires currently live in:

- `lib/wisco/commands/exec.rb`
- `lib/wisco/commands/fixtures.rb`

By contrast, `lib/wisco.rb` only depends on `json`, `thor`, and Wisco's own files.


### ExecCommand
Calling ExecCommand to execute something:

```
require 'workato/cli/exec_command'

cmd = Workato::CLI::ExecCommand.new(
  path: 'actions.some_action.execute',
  options: {
    # CLI-style options hash (symbols)
    connector: 'connector.rb',          # optional; defaults to DEFAULT_CONNECTOR_PATH
    settings: 'settings.yaml',          # optional
    connection: 'default',              # optional connection name inside settings
    key: 'master.key',                  # optional
    input: 'input.json',                # optional; JSON file path
    args: 'args.json',                  # optional; JSON file path (array)
    verbose: true,                      # optional; enables progress + extra printing
    debug: false,                       # optional; true wraps exceptions in DebugExceptionError
    output: nil                         # nil => prints to stdout, or set to 'output.json' to write file
  }
)

result = cmd.call
```
