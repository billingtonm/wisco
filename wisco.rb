require 'json'
require_relative 'lib/config'
require_relative 'lib/connector'
require_relative 'lib/commands/init'
require_relative 'lib/commands/list'
require_relative 'lib/commands/exec'

# Ensure UTF-8 output on Windows (box-drawing characters in tree view)
$stdout.binmode
$stdout.set_encoding('UTF-8')

CLI_NAME = 'wisco'
DISPLAY_NAME = 'Wisco (Workato Connector SDK Companion)'
WISCO_VERSION = '0.1.0'
CONFIG_FILENAME = ".#{CLI_NAME}.json"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

def usage
  puts <<~USAGE
    #{DISPLAY_NAME} v#{WISCO_VERSION}

    Usage:
      #{CLI_NAME} <command> [options]

    Commands:
      init [path]              Detect connector file and create/update #{CONFIG_FILENAME}.
                               Defaults to the current directory.

      list [path]              Show a tree overview of the connector structure.
      list actions [path]      List all actions as a markdown table.
      list triggers [path]     List all triggers as a markdown table.
      list all [path]          Show tree + actions + triggers.

      exec <path> [target_dir]
                               Execute connector methods (default mode).
                               Runs each ready execute_* file in
                               fixtures/<section>/<key>/.

      exec <path> --mode=fields [target_dir]
                               Fetch input_fields and output_fields.

                               <path> forms:
                                 actions.get_users   one key in a known section
                                 actions             all keys in that section
                                 get_users           auto-detect section

                               Options:
                                 --mode=execute      execute action/trigger (default)
                                 --mode=fields       fetch input/output fields
                                 --input=file.json   specific input file (execute mode)
                                 --overwrite=true    overwrite execute_input.json template
                                 --debug             print ExecCommand call details

    Options:
      --help, -h     Show this help message.
      --version, -v  Show version.

  USAGE
end

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

command = ARGV.shift

case command
when nil
  usage
  exit 1
when '--help', '-h'
  usage
when '--version', '-v'
  puts "#{DISPLAY_NAME} v#{WISCO_VERSION}"
when 'init'
  target = ARGV.shift || Dir.pwd
  Wisco::Commands::Init.run(target)
when 'list'
  subcommand = ARGV.shift
  # If arg looks like a path with no subcommand, treat it as the target dir
  if subcommand && subcommand.match?(%r{^[./~\\]|^[A-Za-z]:[/\\]})
    target = subcommand
    subcommand = nil
  else
    target = ARGV.shift || Dir.pwd
  end
  target ||= Dir.pwd
  Wisco::Commands::List.run(subcommand, target)
when 'exec'
  flags      = ARGV.select { |a| a.start_with?('--') }
  positional = ARGV.reject { |a| a.start_with?('--') }

  path_arg = positional.shift
  if path_arg.nil?
    warn "Error: 'exec' requires a path argument (e.g. actions.get_users, actions, get_users)."
    warn "Run '#{CLI_NAME} --help' for usage."
    exit 1
  end

  # Second positional arg is target dir if it looks like a path
  raw_target = positional.shift
  target = if raw_target && raw_target.match?(%r{^[./~\\]|^[A-Za-z]:[/\\]})
             raw_target
           else
             Dir.pwd
           end

  mode_flag      = flags.find { |f| f.start_with?('--mode=') }
  mode           = mode_flag&.split('=', 2)&.last
  overwrite_flag = flags.find { |f| f.start_with?('--overwrite=') }
  overwrite      = overwrite_flag&.split('=', 2)&.last == 'true'
  input_flag     = flags.find { |f| f.start_with?('--input=') }
  input          = input_flag&.split('=', 2)&.last
  debug          = flags.include?('--debug')

  Wisco::Commands::Exec.run(path_arg, mode, target, overwrite: overwrite, input: input, debug: debug)
else
  warn "Error: Unknown command '#{command}'"
  warn "Run '#{CLI_NAME} --help' for usage."
  exit 1
end
