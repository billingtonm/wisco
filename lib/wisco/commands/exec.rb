require 'fileutils'
require 'workato/connector/sdk'
require 'workato/cli/exec_command'
require_relative '../config'
require_relative '../connector'
require_relative '../path_utils'

module Wisco
  module Commands
    module Exec
      module_function

      def run(path_arg, target_dir, input: nil, debug: false)
        target_dir = File.expand_path(target_dir)
        config_path = Wisco.config_path(target_dir)

        unless File.exist?(config_path)
          warn "Error: No #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME} found in #{target_dir}."
          warn "       Run '#{Wisco::CLI_NAME} init' first."
          exit 1
        end

        config = Wisco::Config.load_config(config_path)
        connector_path = config.dig('connector', 'path')
        connector_file = config.dig('connector', 'file')

        if connector_path.nil? || connector_file.nil?
          warn "Error: #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME} is missing connector path/file. Run '#{Wisco::CLI_NAME} init' again."
          exit 1
        end

        connector_full_path = File.join(connector_path, connector_file)
        connection = config['connection']

        connector = Wisco::Connector.load_connector_from_config(target_dir)
        pairs = Wisco::PathUtils.parse_path(path_arg, connector)

        pairs.each do |section, key|
          puts "Executing #{section}.#{key}"
          fixtures_dir = File.join(target_dir, 'fixtures', section, key)
          fixture_dir_output = fixtures_dir.sub(connector_path, '.')

          unless File.directory?(fixtures_dir)
            warn "Error: fixtures directory not found: #{fixture_dir_output}"
            warn "       Run '#{Wisco::CLI_NAME} fixtures #{section}.#{key}' first."
            next
          end

          input_files = resolve_input_files(input, fixtures_dir)

          if input_files.empty?
            warn "\tWarning: No ready input files found in #{fixture_dir_output}"
            next
          end

          input_files.each do |input_file|
            execute_one(section, key, input_file, fixtures_dir,
                        connector_full_path, connection, debug: debug)
          end
        end
      end

      # Resolve the list of input files to execute.
      # If an explicit input filename/path is given, use that (relative to fixtures_dir).
      # Otherwise glob execute_* in fixtures_dir and exclude files still containing the sentinel.
      def resolve_input_files(input, fixtures_dir)
        if input
          path = File.absolute_path?(input) ? input : File.join(fixtures_dir, input)
          unless File.exist?(path)
            warn "Error: Input file not found: #{path}"
            exit 1
          end
          [path]
        else
          Dir.glob(File.join(fixtures_dir, 'execute_*')).select do |f|
            File.file?(f) && !file_has_sentinel?(f)
          end
        end
      end

      def file_has_sentinel?(path)
        first_line = begin
          File.open(path, &:readline).chomp
        rescue StandardError
          ''
        end
        first_line == Wisco::Commands::Fixtures::SENTINEL
      end

      def execute_one(section, key, input_file, fixtures_dir, connector_full_path, connection, debug: false)
        stem        = File.basename(input_file, '.*')
        output_file = File.join(fixtures_dir, "output_#{stem}.json")
        error_file  = File.join(fixtures_dir, "error_#{stem}.txt")

        options = { connector: connector_full_path, input: input_file, output: output_file }
        options[:connection] = connection if connection

        if debug
          warn "[exec] path:       #{section}.#{key}.execute"
          warn "[exec] connector:  #{connector_full_path}"
          warn "[exec] connection: #{connection.inspect}"
          warn "[exec] input:      #{input_file}"
          warn "[exec] output:     #{output_file}"
        end

        begin
          cmd = Workato::CLI::ExecCommand.new(path: "#{section}.#{key}.execute", options: options)
          cmd.call
        rescue StandardError => e
          File.write(error_file, "#{e.class}: #{e.message}\n\n#{e.backtrace.join("\n")}\n")
          warn "Error executing #{section}.#{key} with #{File.basename(input_file)}: #{e.message}"
          warn "  Details written to: #{error_file}"
          return
        end

        FileUtils.rm_f(error_file)

        return unless File.exist?(output_file)

        pretty = JSON.pretty_generate(JSON.parse(File.read(output_file)))
        File.write(output_file, pretty + "\n")
        puts "  Written: #{output_file}"
      end
    end
  end
end
