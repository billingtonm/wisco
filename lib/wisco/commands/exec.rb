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

      def run(path_arg, target_dir, input: nil, pagination: true, verbose: true, debug: false,
              extended: true, closure: nil, config_fields: nil, continue: nil,
              extended_input_schema: nil, extended_output_schema: nil)
        target_dir = File.expand_path(target_dir)
        config_path = Wisco.config_path(target_dir)

        unless File.exist?(config_path)
          Wisco::TerminalOutput.emit_error("Error: No #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME} found in #{target_dir}.")
          Wisco::TerminalOutput.emit_error("       Run '#{Wisco::CLI_NAME} init' first.")
          exit 1
        end

        config = Wisco::Config.load_config(config_path)
        connector_path = config.dig('connector', 'path')
        connector_file = config.dig('connector', 'file')

        if connector_path.nil? || connector_file.nil?
          Wisco::TerminalOutput.emit_error("Error: #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME} is missing connector path/file. Run '#{Wisco::CLI_NAME} init' again.")
          exit 1
        end

        connector_full_path = File.join(connector_path, connector_file)
        connection = config['connection']

        # ── connection test short-circuit ──────────────────────────────────
        if path_arg == 'test'
          run_test(target_dir, connector_full_path, connection, verbose: verbose, debug: debug)
          return
        end

        connector = Wisco::Connector.load_connector_from_config(target_dir)
        pairs = Wisco::PathUtils.parse_path(path_arg, connector)

        pairs.each do |section, key|
          puts "Executing #{section}.#{key}"
          fixtures_dir = File.join(target_dir, 'fixtures', section, key)
          fixture_dir_output = fixtures_dir.sub(connector_path, '.')

          unless File.directory?(fixtures_dir)
            Wisco::TerminalOutput.emit_error("Error: fixtures directory not found: #{fixture_dir_output}")
            Wisco::TerminalOutput.emit_error("       Run '#{Wisco::CLI_NAME} fixtures #{section}.#{key}' first.")
            next
          end

          input_files = resolve_input_files(input, fixtures_dir)

          if input_files.empty?
            if %w[pick_lists methods].include?(section)
              # No-param pick list or method — execute once with no input file
              execute_one(section, key, nil, fixtures_dir, connector_full_path, connection,
                          pagination: pagination, verbose: verbose, extended: extended,
                          closure: closure, config_fields: config_fields, continue: continue,
                          extended_input_schema: extended_input_schema,
                          extended_output_schema: extended_output_schema, debug: debug)
            else
              Wisco::TerminalOutput.emit_warning("  Warning: No ready input files found in #{fixture_dir_output}")
            end
            next
          end

          input_files.each do |input_file|
            execute_one(section, key, input_file, fixtures_dir,
                        connector_full_path, connection, pagination: pagination, verbose: verbose,
                        extended: extended, closure: closure, config_fields: config_fields,
                        continue: continue, extended_input_schema: extended_input_schema,
                        extended_output_schema: extended_output_schema, debug: debug)
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
            Wisco::TerminalOutput.emit_error("Error: Input file not found: #{path}")
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

      # Resolves a user-supplied path option. If the value is a bare filename
      # (no directory component), it is joined to fixtures_dir. Otherwise used as-is.
      def resolve_option_path(value, fixtures_dir)
        return nil if value.nil?
        File.dirname(value) == '.' ? File.join(fixtures_dir, value) : value
      end

      def run_test(target_dir, connector_full_path, connection, verbose: true, debug: false)
        puts "Testing connection"
        fixtures_dir = File.join(target_dir, 'fixtures', 'connection', 'test')
        FileUtils.mkdir_p(fixtures_dir)

        output_file = File.join(fixtures_dir, 'output_test.json')
        error_file  = File.join(fixtures_dir, 'error_test.txt')

        options = { connector: connector_full_path, output: output_file }
        options[:connection] = connection if connection
        options[:verbose]    = verbose

        if debug
          warn "[exec] path:       test"
          warn "[exec] connector:  #{connector_full_path}"
          warn "[exec] connection: #{connection.inspect}"
          warn "[exec] output:     #{output_file}"
        end

        begin
          cmd = Workato::CLI::ExecCommand.new(path: 'test', options: options)
          cmd.call
        rescue StandardError => e
          File.write(error_file, "#{e.class}: #{e.message}\n\n#{e.backtrace.join("\n")}\n")
          Wisco::TerminalOutput.emit_error("Error testing connection: #{e.message}")
          Wisco::TerminalOutput.emit_error("  Details written to: #{error_file}")
          return
        end

        FileUtils.rm_f(error_file)
        return unless File.exist?(output_file)

        pretty = JSON.pretty_generate(JSON.parse(File.read(output_file)))
        File.write(output_file, pretty + "\n")
        puts "  Written: #{output_file}"
      end

      def execute_one(section, key, input_file, fixtures_dir, connector_full_path, connection,
                      pagination: true, verbose: true, debug: false,
                      extended: true, closure: nil, config_fields: nil, continue: nil,
                      extended_input_schema: nil, extended_output_schema: nil)
        stem        = input_file ? File.basename(input_file, '.*') : 'execute'
        output_file = File.join(fixtures_dir, "output_#{stem}.json")
        error_file  = File.join(fixtures_dir, "error_#{stem}.txt")

        use_args  = %w[pick_lists methods].include?(section)
        exec_path = if use_args
                      "#{section}.#{key}"
                    elsif section == 'triggers'
                      pagination ? "#{section}.#{key}.poll" : "#{section}.#{key}.poll_page"
                    else
                      "#{section}.#{key}.execute"
                    end

        options = { connector: connector_full_path, output: output_file }
        options[:connection] = connection if connection
        options[:verbose]    = verbose
        if use_args
          options[:args] = input_file if input_file
        else
          options[:input] = input_file
        end

        # ── pass-through workato exec parameters ───────────────────────────
        options[:closure]       = resolve_option_path(closure,       fixtures_dir) if closure
        options[:config_fields] = resolve_option_path(config_fields, fixtures_dir) if config_fields
        options[:continue]      = resolve_option_path(continue,      fixtures_dir) if continue

        # ── extended schema (actions + triggers only) ───────────────────────
        unless use_args
          eis = if extended_input_schema
                  resolve_option_path(extended_input_schema, fixtures_dir)
                elsif extended
                  f = File.join(fixtures_dir, 'input_fields.json')
                  File.exist?(f) ? f : nil
                end
          options[:extended_input_schema] = eis if eis

          eos = if extended_output_schema
                  resolve_option_path(extended_output_schema, fixtures_dir)
                elsif extended
                  f = File.join(fixtures_dir, 'output_fields.json')
                  File.exist?(f) ? f : nil
                end
          options[:extended_output_schema] = eos if eos

          if verbose
            Wisco::TerminalOutput.emit_info("  [INFO] extended_input_schema:  #{options[:extended_input_schema]}")  if options[:extended_input_schema]
            Wisco::TerminalOutput.emit_info("  [INFO] extended_output_schema: #{options[:extended_output_schema]}") if options[:extended_output_schema]
          end
        end

        if debug
          warn "[exec] path:         #{exec_path}"
          warn "[exec] connector:    #{connector_full_path}"
          warn "[exec] connection:   #{connection.inspect}"
          warn "[exec] #{use_args ? 'args' : 'input'}:        #{input_file.inspect}"
          warn "[exec] output:       #{output_file}"
          warn "[exec] closure:      #{options[:closure].inspect}"              if options[:closure]
          warn "[exec] config_fields:#{options[:config_fields].inspect}"        if options[:config_fields]
          warn "[exec] continue:     #{options[:continue].inspect}"             if options[:continue]
          warn "[exec] ext_input:    #{options[:extended_input_schema].inspect}" if options[:extended_input_schema]
          warn "[exec] ext_output:   #{options[:extended_output_schema].inspect}" if options[:extended_output_schema]
        end

        begin
          cmd = Workato::CLI::ExecCommand.new(path: exec_path, options: options)
          cmd.call
        rescue StandardError => e
          File.write(error_file, "#{e.class}: #{e.message}\n\n#{e.backtrace.join("\n")}\n")
          Wisco::TerminalOutput.emit_error("Error executing #{section}.#{key} with #{input_file ? File.basename(input_file) : 'no input'}: #{e.message}")
          Wisco::TerminalOutput.emit_error("  Details written to: #{error_file}")
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
