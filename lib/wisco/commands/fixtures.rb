require 'fileutils'
require 'workato/connector/sdk'
require 'workato/cli/exec_command'
require_relative '../config'
require_relative '../connector'
require_relative '../path_utils'

module Wisco
  module Commands
    module Fixtures
      SENTINEL = '# Remove this comment before updating. Files that include this line will be overwritten.'

      module_function

      def run(path_arg, target_dir, overwrite: false, debug: false)
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
          puts "Processing #{section}.#{key}"
          fixtures_dir = File.join(target_dir, 'fixtures', section, key)
          FileUtils.mkdir_p(fixtures_dir)

          if section == 'pick_lists'
            process_pick_list(key, connector, fixtures_dir, overwrite: overwrite)
          elsif section == 'methods'
            process_method(key, connector, fixtures_dir, overwrite: overwrite)
          else
            # ── config_fields pre-check ──────────────────────────────────────
            item   = connector[section.to_sym]&.[](key.to_sym)
            raw_cf = item&.[](:config_fields)
            cf_file = File.join(fixtures_dir, 'config_fields.json')
            cf_opt  = nil   # set to cf_file once the user has filled it in

            if raw_cf
              if config_fields_ready?(cf_file)
                cf_opt = cf_file
              else
                write_config_fields_template(raw_cf, cf_file)
                warn "  Written:  #{cf_file}"
                warn "  Action required: fill in config_fields.json, then re-run fixtures."
                next
              end
            end

            # ── input_fields ─────────────────────────────────────────────────
            input_fields_file = File.join(fixtures_dir, 'input_fields.json')
            call_exec(
              path:          "#{section}.#{key}.input_fields",
              connector:     connector_full_path,
              connection:    connection,
              output:        input_fields_file,
              config_fields: cf_opt,
              debug:         debug
            )

            generate_execute_input(input_fields_file, fixtures_dir, overwrite: overwrite, debug: debug)

            # ── output_fields ────────────────────────────────────────────────
            output_fields_file = File.join(fixtures_dir, 'output_fields.json')
            call_exec(
              path:          "#{section}.#{key}.output_fields",
              connector:     connector_full_path,
              connection:    connection,
              output:        output_fields_file,
              config_fields: cf_opt,
              debug:         debug
            )
          end
        end
      end

      # Reads input_fields.json, builds a template hash, writes execute_input.json.
      # The file is prefixed with SENTINEL so it is identifiable as an unedited template.
      # Overwrite rules:
      #   - File absent                  -> write
      #   - File present, sentinel L1    -> overwrite (still a template)
      #   - File present, no sentinel    -> skip (user-edited); force with --overwrite
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

      def process_method(key, connector, fixtures_dir, overwrite: false)
        method_fn = connector[:methods]&.[](key.to_sym)

        unless method_fn.respond_to?(:parameters)
          warn "  Warning: method '#{key}' is not callable — skipping."
          return
        end

        params = method_fn.parameters   # all params are real inputs (no connection to drop)

        if params.empty?
          puts "  No input required: #{fixtures_dir}"
          return
        end

        output_file = File.join(fixtures_dir, 'execute_input.json')

        if File.exist?(output_file)
          first_line = begin
                         File.open(output_file, &:readline).chomp
                       rescue StandardError
                         ''
                       end
          unless first_line == SENTINEL || overwrite
            puts "  Skipped (user-edited): #{output_file}"
            return
          end
        end

        # Positional array — each element is the param name as a placeholder string
        template = params.map { |(_, name)| name.to_s }
        content  = "#{SENTINEL}\n#{JSON.pretty_generate(template)}\n"
        File.write(output_file, content)
        puts "  Written: #{output_file}"
      end

      def process_pick_list(key, connector, fixtures_dir, overwrite: false)
        pick_list_fn = connector[:pick_lists]&.[](key.to_sym)

        unless pick_list_fn.respond_to?(:parameters)
          warn "  Warning: pick_list '#{key}' is not callable — skipping."
          return
        end

        # Drop the first parameter (connection); remaining params become input fields
        input_params = pick_list_fn.parameters.drop(1)

        if input_params.empty?
          puts "  No input required: #{fixtures_dir}"
          return
        end

        output_file = File.join(fixtures_dir, 'execute_input.json')

        if File.exist?(output_file)
          first_line = begin
                         File.open(output_file, &:readline).chomp
                       rescue StandardError
                         ''
                       end
          unless first_line == SENTINEL || overwrite
            puts "  Skipped (user-edited): #{output_file}"
            return
          end
        end

        template = input_params.each_with_object({}) do |(_, name), hash|
          hash[name.to_s] = '<string_value_required>'
        end
        content = "#{SENTINEL}\n#{JSON.pretty_generate(template)}\n"
        File.write(output_file, content)
        puts "  Written: #{output_file}"
      end

      def config_fields_ready?(path)
        return false unless File.exist?(path)

        first_line = begin
                       File.open(path, &:readline).chomp
                     rescue StandardError
                       ''
                     end
        first_line != SENTINEL
      end

      def write_config_fields_template(config_fields_array, output_file)
        stringified = stringify_keys_deep(config_fields_array)
        template    = schema_to_template(stringified)
        content     = "#{SENTINEL}\n#{JSON.pretty_generate(template)}\n"
        File.write(output_file, content)
      end

      def stringify_keys_deep(obj)
        case obj
        when Hash  then obj.transform_keys(&:to_s).transform_values { |v| stringify_keys_deep(v) }
        when Array then obj.map { |e| stringify_keys_deep(e) }
        else            obj
        end
      end

      def call_exec(path:, connector:, connection:, output:, config_fields: nil, debug: false)
        options = { connector: connector, output: output }
        options[:connection]    = connection    if connection
        options[:config_fields] = config_fields if config_fields

        if debug
          warn "[fixtures] path:       #{path}"
          warn "[fixtures] connector:  #{connector}"
          warn "[fixtures] connection: #{connection.inspect}"
          warn "[fixtures] output:     #{output}"
        end

        cmd = Workato::CLI::ExecCommand.new(path: path, options: options)
        begin
          cmd.call
        rescue StandardError => e
          warn "  Warning: #{path} failed — #{e.message}"
          return
        end

        return unless File.exist?(output)

        pretty = JSON.pretty_generate(JSON.parse(File.read(output)))
        File.write(output, pretty + "\n")
      end
    end
  end
end
