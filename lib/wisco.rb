require 'json'
require 'thor'
require_relative 'wisco/version'

module Wisco
  CLI_NAME        = 'wisco'
  DISPLAY_NAME    = 'Wisco (Workato Connector SDK Companion)'
  WISCO_DIR       = ".#{CLI_NAME}"
  CONFIG_FILENAME = 'config.json'

  def self.config_path(target_dir)
    File.join(target_dir, WISCO_DIR, CONFIG_FILENAME)
  end
end

require_relative 'wisco/config'
require_relative 'wisco/connector'
require_relative 'wisco/commands/init'
require_relative 'wisco/commands/list'
require_relative 'wisco/commands/exec'
require_relative 'wisco/commands/fixtures'
require_relative 'wisco/commands/pull'

module Wisco
  class CLI < Thor
    package_name DISPLAY_NAME
    check_unknown_options!

    def self.exit_on_failure?
      true
    end

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

    desc 'init [PATH]', "Detect connector and initialise #{WISCO_DIR}/"
    long_desc "Searches PATH (default: current directory) for a valid connector file and writes #{WISCO_DIR}/#{CONFIG_FILENAME}."
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
      Runs each ready execute_* file in fixtures/<section>/<key>/.
      Run `wisco fixtures PATH` first to generate fixture templates.

      PATH forms:
        actions.get_users   one key in a known section
        actions             all keys in that section
        get_users           auto-detect section
    DESC
    option :input, type: :string,  desc: 'Specific input file'
    option :debug, type: :boolean, default: false, desc: 'Print ExecCommand call details'
    def exec(path_arg, target_dir = nil)
      Wisco::Commands::Exec.run(
        path_arg,
        target_dir || Dir.pwd,
        input: options[:input],
        debug: options[:debug]
      )
    end

    desc 'fixtures PATH [TARGET_DIR]', 'Fetch input/output fields and generate fixture templates'
    long_desc <<~DESC
      Fetches input_fields and output_fields from the connector and writes them
      to fixtures/<section>/<key>/. Also generates an execute_input.json template.

      PATH forms:
        actions.get_users   one key in a known section
        actions             all keys in that section
        get_users           auto-detect section
    DESC
    option :overwrite, type: :boolean, default: false, desc: 'Overwrite execute_input.json even if user-edited'
    option :debug,     type: :boolean, default: false, desc: 'Print ExecCommand call details'
    def fixtures(path_arg, target_dir = nil)
      Wisco::Commands::Fixtures.run(
        path_arg,
        target_dir || Dir.pwd,
        overwrite: options[:overwrite],
        debug:     options[:debug]
      )
    end

    desc 'pull [TARGET_DIR]', 'Pull connector from the Workato platform'
    long_desc <<~DESC
      Downloads connector data from the Workato Developer API.
      Saves results to .wisco/pull/ inside the target directory.

      Requires workato_developer_api hostname and api_token in #{WISCO_DIR}/#{CONFIG_FILENAME}.
      If not set, you will be prompted on first run.

      --what accepts comma-separated values: all, logo, code, versions, meta
    DESC
    option :what,  type: :string,  default: 'all',
                   desc: 'What to retrieve: all, logo, code, versions, meta'
    option :title, type: :string,  desc: 'Connector title to search for (default: derived from connector file)'
    option :debug, type: :boolean, default: false, desc: 'Show API call details'
    def pull(target_dir = nil)
      Wisco::Commands::Pull.run(
        target_dir || Dir.pwd,
        what:  options[:what],
        title: options[:title],
        debug: options[:debug]
      )
    end
  end
end
