require 'json'
require 'thor'
require_relative 'wisco/version'

module Wisco
  CLI_NAME        = 'wisco'
  DISPLAY_NAME    = 'Wisco (Workato Connector SDK Companion)'
  CONFIG_FILENAME = ".#{CLI_NAME}.json"
end

require_relative 'wisco/config'
require_relative 'wisco/connector'
require_relative 'wisco/commands/init'
require_relative 'wisco/commands/list'
require_relative 'wisco/commands/exec'

module Wisco
  class CLI < Thor
    package_name DISPLAY_NAME

    # Rewrite `wisco <command> --help` → `wisco help <command>` so Thor shows
    # per-command help instead of treating --help as a positional argument.
    def self.start(given_args = ARGV, config = {})
      if given_args.length >= 2 &&
         (given_args.include?('--help') || given_args.include?('-h')) &&
         !given_args.first.start_with?('-')
        super(['help', given_args.first], config)
      else
        super
      end
    end

    map %w[--version -v] => :version
    desc 'version', 'Show version'
    def version
      puts "#{DISPLAY_NAME} v#{VERSION}"
    end

    desc 'init [PATH]', "Detect connector and create/update #{CONFIG_FILENAME}"
    long_desc "Searches PATH (default: current directory) for a valid connector file and writes #{CONFIG_FILENAME}."
    def init(path = nil)
      Wisco::Commands::Init.run(path || Dir.pwd)
    end

    desc 'list [SUBCOMMAND] [PATH]', 'Show connector structure'
    long_desc <<~DESC
      Shows a tree overview by default. SUBCOMMAND can be:
        actions   List all actions as a markdown table
        triggers  List all triggers as a markdown table
        all       Show tree + actions + triggers
      PATH defaults to the current directory.
    DESC
    option :sort, type: :string, desc: 'Sort actions/triggers by key or title', enum: %w[key title]
    def list(subcommand = nil, path = nil)
      if subcommand&.match?(%r{^[./~\\]|^[A-Za-z]:[/\\]})
        path = subcommand
        subcommand = nil
      end
      Wisco::Commands::List.run(subcommand, path || Dir.pwd, sort: options[:sort])
    end

    desc 'exec PATH [TARGET_DIR]', 'Execute connector methods against fixture data'
    long_desc <<~DESC
      PATH forms:
        actions.get_users   one key in a known section
        actions             all keys in that section
        get_users           auto-detect section
    DESC
    option :mode,      type: :string,  default: 'execute', desc: 'execute or fields', enum: %w[execute fields]
    option :input,     type: :string,  desc: 'Specific input file (execute mode only)'
    option :overwrite, type: :boolean, default: false, desc: 'Overwrite execute_input.json template'
    option :debug,     type: :boolean, default: false, desc: 'Print ExecCommand call details'
    def exec(path_arg, target_dir = nil)
      Wisco::Commands::Exec.run(
        path_arg,
        options[:mode],
        target_dir || Dir.pwd,
        overwrite: options[:overwrite],
        input:     options[:input],
        debug:     options[:debug]
      )
    end
  end
end
