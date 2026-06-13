require 'fileutils'
require 'tempfile'
require 'workato/connector/sdk'
require 'workato/cli/exec_command'
require_relative '../config'
require_relative '../connector'
require_relative '../path_utils'
require_relative '../exec_script'

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

          input_files = resolve_input_files(input, fixtures_dir, debug: debug)

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
            if File.extname(input_file).downcase == '.rb'
              execute_ruby_script(section, key, input_file, fixtures_dir, target_dir,
                                  connector_full_path, connection, config,
                                  pagination: pagination, verbose: verbose,
                                  extended: extended, closure: closure, config_fields: config_fields,
                                  continue: continue, extended_input_schema: extended_input_schema,
                                  extended_output_schema: extended_output_schema, debug: debug)
            else
              execute_one(section, key, input_file, fixtures_dir,
                          connector_full_path, connection, pagination: pagination, verbose: verbose,
                          extended: extended, closure: closure, config_fields: config_fields,
                          continue: continue, extended_input_schema: extended_input_schema,
                          extended_output_schema: extended_output_schema, debug: debug)
            end
          end
        end
      end

      # Resolve the list of input files to execute.
      # If an explicit input filename/path is given, use that (relative to fixtures_dir).
      # Otherwise glob execute_*.{json,rb} in fixtures_dir and exclude files still containing
      # their respective sentinel.
      #
      # In debug mode, prints which candidate files were found and which were
      # skipped (because they still contain a sentinel comment).
      def resolve_input_files(input, fixtures_dir, debug: false)
        if input
          path = File.absolute_path?(input) ? input : File.join(fixtures_dir, input)
          unless File.exist?(path)
            Wisco::TerminalOutput.emit_error("Error: Input file not found: #{path}")
            exit 1
          end
          [path]
        else
          candidates = Dir.glob(File.join(fixtures_dir, 'execute_*.{json,rb}')).select { |f| File.file?(f) }
          warn "[exec] candidate files: #{candidates.map { |f| File.basename(f) }}" if debug
          candidates.reject do |f|
            if file_has_sentinel?(f)
              warn "[exec]   skipped (sentinel): #{File.basename(f)}" if debug
              true
            else
              false
            end
          end
        end
      end

      # Returns true if the file should be skipped. Each input format has its own
      # sentinel convention:
      #   .json — first line exactly equals Wisco::Commands::Fixtures::SENTINEL
      #   .rb   — first non-blank line matches `# WISCO_SKIP`
      def file_has_sentinel?(path)
        if File.extname(path).downcase == '.rb'
          return Wisco::ExecScript.sentinel?(path)
        end

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
          if input_file && section == 'methods'
            options[:args] = normalize_method_args(input_file)
          elsif input_file
            options[:args] = input_file
          end
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
          FileUtils.rm_f(output_file)
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

      # Handles `execute_*.rb` scripts: evaluates the script to produce dynamic
      # input, writes it to <subdir>/input.json, runs the connector item via
      # ExecCommand, and writes <subdir>/output.json or <subdir>/error.txt.
      # The subdirectory is named after the script (without .rb), e.g.
      # execute_input.rb -> execute_input/.
      def execute_ruby_script(section, key, script_path, fixtures_dir, target_dir,
                              connector_full_path, connection, config,
                              pagination: true, verbose: true, debug: false,
                              extended: true, closure: nil, config_fields: nil, continue: nil,
                              extended_input_schema: nil, extended_output_schema: nil)
        subdir      = File.join(fixtures_dir, File.basename(script_path, '.rb'))
        FileUtils.mkdir_p(subdir)
        input_file  = File.join(subdir, 'input.json')
        output_file = File.join(subdir, 'output.json')
        error_file  = File.join(subdir, 'error.txt')

        # Step 1: evaluate the script to obtain dynamic input
        connection_name = config['connection'] || 'default'

        begin
          generated = Wisco::ExecScript.evaluate(
            script_path:         script_path,
            connector_full_path: connector_full_path,
            target_dir:          target_dir,
            connection_name:     connection_name
          )
        rescue StandardError => e
          FileUtils.rm_f(input_file)
          FileUtils.rm_f(output_file)
          File.write(error_file, "#{e.class}: #{e.message}\n\n#{Array(e.backtrace).join("\n")}\n")
          Wisco::TerminalOutput.emit_error("Error evaluating #{File.basename(script_path)}: #{e.message}")
          Wisco::TerminalOutput.emit_error("  Details written to: #{error_file}")
          return
        end

        File.write(input_file, JSON.pretty_generate(generated) + "\n")
        puts "  Generated: #{input_file}"

        # Step 2: build ExecCommand options (mirrors execute_one)
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
          options[:args] = section == 'methods' ? normalize_ruby_method_args(input_file) : input_file
        else
          options[:input] = input_file
        end

        options[:closure]       = resolve_option_path(closure,       fixtures_dir) if closure
        options[:config_fields] = resolve_option_path(config_fields, fixtures_dir) if config_fields
        options[:continue]      = resolve_option_path(continue,      fixtures_dir) if continue

        # extended schema files still live at the item's fixtures_dir (not the subdir)
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
        end

        if debug
          warn "[exec.rb] script:      #{script_path}"
          warn "[exec.rb] subdir:      #{subdir}"
          warn "[exec.rb] path:        #{exec_path}"
          warn "[exec.rb] connector:   #{connector_full_path}"
          warn "[exec.rb] connection:  #{connection.inspect}"
          warn "[exec.rb] #{use_args ? 'args' : 'input'}:       #{input_file}"
          warn "[exec.rb] output:      #{output_file}"
        end

        # Step 3: invoke ExecCommand against the generated input
        begin
          cmd = Workato::CLI::ExecCommand.new(path: exec_path, options: options)
          cmd.call
        rescue StandardError => e
          FileUtils.rm_f(input_file)
          FileUtils.rm_f(output_file)
          File.write(error_file, "#{e.class}: #{e.message}\n\n#{e.backtrace.join("\n")}\n")
          Wisco::TerminalOutput.emit_error("Error executing #{section}.#{key} with #{File.basename(script_path)}: #{e.message}")
          Wisco::TerminalOutput.emit_error("  Details written to: #{error_file}")
          return
        end

        FileUtils.rm_f(error_file)

        return unless File.exist?(output_file)

        pretty = JSON.pretty_generate(JSON.parse(File.read(output_file)))
        File.write(output_file, pretty + "\n")
        puts "  Written: #{output_file}"
      end

      # The Workato SDK's InvokePath#invoke_method applies Array.wrap(args.last).flatten(1)
      # when the last parameter is *args, which incorrectly unwraps array-valued positional
      # arguments one level too many. These helpers compensate by pre-wrapping Array elements
      # so that flatten(1) cancels out and the method receives the correct value.

      # For JSON execute_input files (positional-args array format):
      # [[{h1},{h2}]] → [[[{h1},{h2}]]] so SDK flatten(1) restores [[{h1},{h2}]] → method([{h1},{h2}])
      def normalize_method_args(input_file)
        parsed = JSON.parse(File.read(input_file))
        return input_file unless parsed.is_a?(Array) && parsed.any? { |a| a.is_a?(Array) }

        fixed = parsed.map { |a| a.is_a?(Array) ? [a] : a }
        tmp = Tempfile.new(['wisco_args_', '.json'])
        tmp.write(JSON.generate(fixed))
        tmp.close
        tmp.path
      end

      # For Ruby-script-generated input files (direct argument value):
      # [{h1},{h2}] → [[{h1},{h2}]] so SDK flatten(1) restores [{h1},{h2}] → method([{h1},{h2}])
      def normalize_ruby_method_args(input_file)
        parsed = JSON.parse(File.read(input_file))
        return input_file unless parsed.is_a?(Array)

        tmp = Tempfile.new(['wisco_args_', '.json'])
        tmp.write(JSON.generate([parsed]))
        tmp.close
        tmp.path
      end
    end
  end
end
