require 'json'
require 'thor'
require_relative 'wisco/version'
require_relative 'wisco/terminal_output'

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
require_relative 'wisco/profile'
require_relative 'wisco/connector'
require_relative 'wisco/commands/init'
require_relative 'wisco/commands/list'
require_relative 'wisco/commands/exec'
require_relative 'wisco/commands/fixtures'
require_relative 'wisco/commands/pull'
require_relative 'wisco/commands/push'
require_relative 'wisco/commands/schema'
require_relative 'wisco/commands/profile'

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
    option :profile, type: :string, desc: 'Attach a named connection profile instead of entering credentials manually'
    def init(path = nil)
      Wisco::Commands::Init.run(path || Dir.pwd, profile: options[:profile])
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
    option :input,      type: :string,  desc: 'Specific input file'
    option :pagination, type: :boolean, default: true,
                        desc: 'Triggers only: true = .poll (with pagination), false = .poll_page (without)'
    option :verbose,    type: :boolean, default: false, desc: 'Enable detailed SDK logging'
    option :extended,   type: :boolean, default: true,
                        desc: 'Auto-pass input_fields/output_fields as extended schema (actions/triggers)'
    option :closure,                  type: :string, desc: 'Closure JSON file (triggers: simulate subsequent polls)'
    option :'config-fields',          type: :string, desc: 'config_fields JSON file'
    option :continue,                 type: :string, desc: 'Continue JSON file (multistep actions)'
    option :'extended-input-schema',  type: :string, desc: 'Extended input schema JSON (overrides --extended auto-detection)'
    option :'extended-output-schema', type: :string, desc: 'Extended output schema JSON (overrides --extended auto-detection)'
    option :debug,      type: :boolean, default: false, desc: 'Print ExecCommand call details'
    def exec(path_arg, target_dir = nil)
      Wisco::Commands::Exec.run(
        path_arg,
        target_dir || Dir.pwd,
        input:                  options[:input],
        pagination:             options[:pagination],
        verbose:                options[:verbose],
        extended:               options[:extended],
        closure:                options[:closure],
        config_fields:          options[:config_fields],
        continue:               options[:continue],
        extended_input_schema:  options[:extended_input_schema],
        extended_output_schema: options[:extended_output_schema],
        debug:                  options[:debug]
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
    option :ruby,      type: :boolean, default: false,
                       desc: 'Also scaffold an execute_input.rb template for dynamic input scripts'
    option :debug,     type: :boolean, default: false, desc: 'Print ExecCommand call details'
    def fixtures(path_arg, target_dir = nil)
      Wisco::Commands::Fixtures.run(
        path_arg,
        target_dir || Dir.pwd,
        overwrite: options[:overwrite],
        ruby:      options[:ruby],
        debug:     options[:debug]
      )
    end

    desc 'push [TARGET_DIR]', 'Push connector assets to the Workato platform'
    long_desc <<~DESC
      Uploads the connector code, logo.png, and README.md to Workato.
      Requires workato_developer_api hostname and api_token in #{WISCO_DIR}/#{CONFIG_FILENAME}.
      If not set, you will be prompted on first run.
    DESC
    option :title,   type: :string,  desc: 'Connector title (default: from config or connector code)'
    option :notes,   type: :string,  desc: 'Version notes (prompted if not provided)'
    option :folder,  type: :numeric, desc: 'Workato folder ID to push connector into'
    option :verbose, type: :boolean, default: false, desc: 'Enable detailed SDK logging'
    option :debug,   type: :boolean, default: false, desc: 'Show push call details'
    def push(target_dir = nil)
      Wisco::Commands::Push.run(
        target_dir || Dir.pwd,
        title:   options[:title],
        notes:   options[:notes],
        folder:  options[:folder],
        verbose: options[:verbose],
        debug:   options[:debug]
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

    desc 'profile SUBCOMMAND ...ARGS', 'Manage connection profiles (~/.wisco/profiles.yaml)'
    long_desc <<~DESC
      Subcommands:
        add [NAME]     Create a new profile
        list           List all profiles
        show NAME      Show profile details
        edit NAME      Update a profile's hostname or API token
        remove NAME    Remove a profile
        use NAME       Attach a profile to this connector project
        extract [NAME] Save this project's inline credentials as a profile
        current        Show which profile this project is using
    DESC
    subcommand 'profile', Wisco::Commands::Profile

    desc 'schema INPUT_FILE [TARGET_DIR]', 'Generate a schema from a JSON or CSV sample file'
    long_desc <<~DESC
      Calls the Workato API to generate a schema from a sample JSON or CSV file.
      File type is auto-detected from the extension (.json or .csv).
      Output defaults to Ruby hash format; use --format=json for raw JSON.

      Requires workato_developer_api hostname and api_token in #{WISCO_DIR}/#{CONFIG_FILENAME}.
      If not set, you will be prompted on first run.
    DESC
    option :format,        type: :string,  default: 'ruby',       enum: %w[ruby json],
                           desc: 'Output format: ruby (default) or json'
    option :ruby_options,  type: :string,  default: 'multi_line', enum: %w[single_line multi_line],
                           desc: 'Ruby output style: single_line or multi_line (default)'
    option :'col-sep',     type: :string,  default: 'comma',
                           enum: %w[comma space tab colon semicolon pipe],
                           desc: 'CSV column separator (default: comma)'
    option :save,          type: :string,  lazy_default: '',
                           desc: 'Save output to file. Omit value to auto-name from input file ' \
                                 '(e.g. input.json → input.schema.rb / input.schema.json)'
    option :debug,         type: :boolean, default: false,         desc: 'Show API call details'
    def schema(input_file, target_dir = nil)
      Wisco::Commands::Schema.run(
        input_file,
        target_dir || Dir.pwd,
        format:       options[:format],
        ruby_options: options[:ruby_options],
        col_sep:      options[:col_sep],
        output:       options[:save],
        debug:        options[:debug]
      )
    end
  end
end
