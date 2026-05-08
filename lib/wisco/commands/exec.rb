require 'fileutils'
require 'thor'
require 'workato/connector/sdk'
require 'workato/cli/exec_command'
require_relative '../config'
require_relative '../connector'

module Wisco
  module Commands
    module Exec
      VALID_SECTIONS = %w[actions triggers].freeze
      SENTINEL = '# Remove this comment before updating. Files that include this line will be overwritten.'

      module_function

      def run(path_arg, mode, target_dir, overwrite: false, input: nil, debug: false)
        case mode
        when nil, 'execute'
          run_execute(path_arg, target_dir, input: input, debug: debug)
        when 'fields'
          run_fields(path_arg, target_dir, overwrite: overwrite, debug: debug)
        else
          warn "Error: Unknown exec mode '#{mode}'."
          warn "Run '#{Wisco::CLI_NAME} --help' for usage."
          exit 1
        end
      end

      def run_execute(path_arg, target_dir, input: nil, debug: false)
        target_dir = File.expand_path(target_dir)
        config_path = File.join(target_dir, Wisco::CONFIG_FILENAME)

        unless File.exist?(config_path)
          warn "Error: No #{Wisco::CONFIG_FILENAME} found in #{target_dir}."
          warn "       Run '#{Wisco::CLI_NAME} init' first."
          exit 1
        end

        config = Wisco::Config.load_config(config_path)
        connector_path = config.dig('connector', 'path')
        connector_file = config.dig('connector', 'file')

        if connector_path.nil? || connector_file.nil?
          warn "Error: #{Wisco::CONFIG_FILENAME} is missing connector path/file. Run '#{Wisco::CLI_NAME} init' again."
          exit 1
        end

        connector_full_path = File.join(connector_path, connector_file)
        connection = config['connection']

        connector = Wisco::Connector.load_connector_from_config(target_dir)
        pairs = parse_path(path_arg, connector)

        pairs.each do |section, key|
          puts "Executing #{section}.#{key}"
          fixtures_dir = File.join(target_dir, 'fixtures', section, key)
          fixture_dir_output = fixtures_dir.sub(connector_path, '.')

          unless File.directory?(fixtures_dir)
            warn "Error: fixtures directory not found: #{fixture_dir_output}"
            warn "       Run '#{Wisco::CLI_NAME} exec #{section}.#{key} --mode=fields' first."
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
        first_line == SENTINEL
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

      def run_fields(path_arg, target_dir, overwrite: false, debug: false)
        target_dir = File.expand_path(target_dir)
        config_path = File.join(target_dir, Wisco::CONFIG_FILENAME)

        unless File.exist?(config_path)
          warn "Error: No #{Wisco::CONFIG_FILENAME} found in #{target_dir}."
          warn "       Run '#{Wisco::CLI_NAME} init' first."
          exit 1
        end

        config = Wisco::Config.load_config(config_path)
        connector_path = config.dig('connector', 'path')
        connector_file = config.dig('connector', 'file')

        if connector_path.nil? || connector_file.nil?
          warn "Error: #{Wisco::CONFIG_FILENAME} is missing connector path/file. Run '#{Wisco::CLI_NAME} init' again."
          exit 1
        end

        connector_full_path = File.join(connector_path, connector_file)
        connection = config['connection'] # may be nil

        connector = Wisco::Connector.load_connector_from_config(target_dir)
        pairs = parse_path(path_arg, connector)

        pairs.each do |section, key|
          puts "Processing #{section}.#{key}"
          fixtures_dir = File.join(target_dir, 'fixtures', section, key)
          FileUtils.mkdir_p(fixtures_dir)

          # Step 1: fetch input_fields
          input_fields_file = File.join(fixtures_dir, 'input_fields.json')
          call_exec(
            path: "#{section}.#{key}.input_fields",
            connector: connector_full_path,
            connection: connection,
            output: input_fields_file,
            debug: debug
          )

          # Step 2: generate execute_input template from input_fields schema
          generate_execute_input(input_fields_file, fixtures_dir, overwrite: overwrite, debug: debug)

          # Step 3: fetch output_fields
          output_fields_file = File.join(fixtures_dir, 'output_fields.json')
          call_exec(
            path: "#{section}.#{key}.output_fields",
            connector: connector_full_path,
            connection: connection,
            output: output_fields_file,
            debug: debug
          )
        end
      end

      # Reads input_fields.json, builds a template hash, writes execute_input.json.
      # The file is prefixed with SENTINEL so it is identifiable as an unedited template.
      # Overwrite rules:
      #   - File absent                  -> write
      #   - File present, sentinel L1    -> overwrite (still a template)
      #   - File present, no sentinel    -> skip (user-edited); force with --overwrite=true
      def generate_execute_input(input_fields_file, fixtures_dir, overwrite: false, debug: false)
        return unless File.exist?(input_fields_file)

        fields = JSON.parse(File.read(input_fields_file))
        return if fields.empty?

        output_file = File.join(fixtures_dir, 'execute_input.json')

        if File.exist?(output_file)
          first_line = begin
            File.open(output_file, &:readline).chomp
          rescue StandardError
            ''
          end
          has_sentinel = (first_line == SENTINEL)

          unless has_sentinel || overwrite
            puts "  Skipped (user-edited): #{output_file}" if debug
            return
          end
        end

        template = schema_to_template(fields)
        content  = "#{SENTINEL}\n#{JSON.pretty_generate(template)}\n"
        File.write(output_file, content)
        puts "  Written: #{output_file}"
      end

      # Recursively converts a Workato schema array into a template hash.
      # Scalars become "<type_value_required|optional>" placeholder strings.
      # Objects expand into a nested hash via their properties.
      # Arrays expand into a single-element array via their properties.
      def schema_to_template(fields)
        fields.each_with_object({}) do |field, hash|
          name     = field['name']
          type     = field['type'] || 'string'
          optional = field.fetch('optional', true)
          req_str  = optional ? 'optional' : 'required'

          hash[name] = case type
                       when 'object'
                         schema_to_template(field['properties'] || [])
                       when 'array'
                         [schema_to_template(field['properties'] || [])]
                       else
                         "<#{type}_value_#{req_str}>"
                       end
        end
      end

      # Returns an array of [section, key] pairs derived from path_arg.
      #
      # Accepted forms:
      #   "section.key"  — one specific key in a known section
      #   "section"      — all keys in that section
      #   "key"          — auto-detect section; error if found in both or neither
      def parse_path(path_arg, connector)
        parts = path_arg.split('.', 2)

        if parts.size == 2
          section, key = parts
          unless VALID_SECTIONS.include?(section)
            warn "Error: Invalid section '#{section}'. Valid sections: #{VALID_SECTIONS.join(', ')}."
            exit 1
          end
          items = connector[section.to_sym]
          unless items&.key?(key.to_sym)
            warn "Error: '#{key}' not found in #{section}."
            exit 1
          end
          [[section, key]]

        elsif VALID_SECTIONS.include?(path_arg)
          section = path_arg
          items = connector[section.to_sym]
          if items.nil? || items.empty?
            warn "Error: No keys found in #{section}."
            exit 1
          end
          items.keys.map { |k| [section, k.to_s] }

        else
          key = path_arg
          in_actions  = connector[:actions]&.key?(key.to_sym)  || false
          in_triggers = connector[:triggers]&.key?(key.to_sym) || false

          case [in_actions, in_triggers]
          when [true, false]  then [['actions',  key]]
          when [false, true]  then [['triggers', key]]
          when [true, true]
            warn "Error: '#{key}' exists in both actions and triggers."
            warn "       Qualify with section, e.g. 'actions.#{key}'."
            exit 1
          else
            warn "Error: '#{key}' not found in actions or triggers."
            exit 1
          end
        end
      end

      def call_exec(path:, connector:, connection:, output:, debug: false)
        options = { connector: connector, output: output }
        options[:connection] = connection if connection

        if debug
          warn "[exec] path:       #{path}"
          warn "[exec] connector:  #{connector}"
          warn "[exec] connection: #{connection.inspect}"
          warn "[exec] output:     #{output}"
        end

        cmd = Workato::CLI::ExecCommand.new(path: path, options: options)
        cmd.call

        # ExecCommand writes compact JSON; rewrite as pretty-printed
        return unless File.exist?(output)

        pretty = JSON.pretty_generate(JSON.parse(File.read(output)))
        File.write(output, pretty + "\n")
      end
    end
  end
end
