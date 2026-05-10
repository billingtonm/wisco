require 'workato/cli/push_command'
require_relative '../config'
require_relative '../connector'

module Wisco
  module Commands
    module Push
      REQUIRED_ASSETS = [
        ->(connector_path, connector_file) { File.join(connector_path, connector_file) },
        ->(connector_path, _)              { File.join(connector_path, 'logo.png') },
        ->(connector_path, _)              { File.join(connector_path, 'README.md') }
      ].freeze

      module_function

      def run(target_dir, title:, notes:, folder:, verbose:, debug:)
        target_dir  = File.expand_path(target_dir)
        config_path = Wisco.config_path(target_dir)

        unless File.exist?(config_path)
          warn "Error: No #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME} found in #{target_dir}."
          warn "       Run '#{Wisco::CLI_NAME} init' first."
          exit 1
        end

        config = Wisco::Config.load_config(config_path)
        config = Wisco::Config.ensure_api_config(config, config_path)

        connector_path = config.dig('connector', 'path')
        connector_file = config.dig('connector', 'file')

        if connector_path.nil? || connector_file.nil?
          warn "Error: #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME} is missing connector path/file. Run '#{Wisco::CLI_NAME} init' again."
          exit 1
        end

        # Check all required assets exist before attempting the push
        check_assets(connector_path, connector_file)

        # Resolve title — save to config if obtained from option or prompt
        title = resolve_title(title, config, config_path, target_dir)

        # Resolve notes — prompt if not provided via --notes
        notes = resolve_notes(notes)

        options = {
          environment: config.dig('workato_developer_api', 'hostname'),
          api_token:   config.dig('workato_developer_api', 'api_token'),
          connector:   connector_file,
          title:       title,
          notes:       notes,
          verbose:     verbose
        }
        options[:folder] = folder if folder

        if debug
          warn "[push] environment: #{options[:environment]}"
          warn "[push] connector:   #{options[:connector]}"
          warn "[push] title:       #{options[:title]}"
          warn "[push] notes:       #{options[:notes]}"
          warn "[push] folder:      #{folder.inspect}"
          warn "[push] verbose:     #{verbose}"
        end

        Dir.chdir(connector_path) do
          Workato::CLI::PushCommand.new(options: options).call
        end
      end

      # ── helpers ──────────────────────────────────────────────────────────

      def check_assets(connector_path, connector_file)
        missing = REQUIRED_ASSETS
                  .map { |fn| fn.call(connector_path, connector_file) }
                  .reject { |path| File.exist?(path) }

        return if missing.empty?

        missing.each { |path| warn "Error: Required asset not found: #{path}" }
        exit 1
      end

      def resolve_title(title, config, config_path, target_dir)
        # 1. Explicit --title option
        if title
          save_title(title, config, config_path)
          return title
        end

        # 2. Stored in config
        stored = config.dig('connector', 'title')
        return stored if stored && !stored.strip.empty?

        # 3. From connector code
        connector = Wisco::Connector.load_connector_from_config(target_dir)
        code_title = connector[:title]
        return code_title if code_title && !code_title.strip.empty?

        # 4. Prompt user
        print 'Connector title not found. Enter a title: '
        title = $stdin.gets.strip
        if title.empty?
          warn 'Error: A connector title is required.'
          exit 1
        end
        save_title(title, config, config_path)
        title
      end

      def save_title(title, config, config_path)
        config['connector'] ||= {}
        config['connector']['title'] = title
        Wisco::Config.save_config(config_path, config)
      end

      def resolve_notes(notes)
        return notes if notes && !notes.strip.empty?

        print 'Version notes (press Enter to leave blank): '
        $stdin.gets.strip
      end
    end
  end
end
