require 'rest-client'
require 'json'
require_relative '../config'
require_relative '../terminal_output'

module Wisco
  module Commands
    module Schema
      API_GENERATE_SCHEMA_PATH = '/api/sdk/generate_schema'
      KEY_ORDER                = %w[name label type of control_type convert_input convert_output].freeze
      SYMBOL_VALUE_KEYS        = %w[type of].freeze

      module_function

      def run(input_file, target_dir, format:, ruby_options:, col_sep:, output:, debug:)
        input_file = File.expand_path(input_file)
        target_dir = File.expand_path(target_dir)

        unless File.exist?(input_file)
          Wisco::TerminalOutput.emit_error("Error: Input file not found: #{input_file}")
          exit 1
        end

        ext = File.extname(input_file).downcase
        unless %w[.json .csv].include?(ext)
          Wisco::TerminalOutput.emit_error("Error: Unsupported file type '#{ext}'. Must be .json or .csv.")
          exit 1
        end

        config_path = Wisco.config_path(target_dir)
        unless File.exist?(config_path)
          Wisco::TerminalOutput.emit_error("Error: No #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME} found in #{target_dir}.")
          Wisco::TerminalOutput.emit_error("       Run '#{Wisco::CLI_NAME} init' first.")
          exit 1
        end

        config    = Wisco::Config.load_config(config_path)
        config    = Wisco::Config.ensure_api_config(config, config_path)
        hostname  = config.dig('workato_developer_api', 'hostname')
        api_token = config.dig('workato_developer_api', 'api_token')

        schema = fetch_schema(input_file, hostname, api_token, col_sep: col_sep, debug: debug)

        formatted = if format == 'json'
                      format_json(schema)
                    else
                      format_ruby(schema, style: ruby_options.to_sym)
                    end

        output_path = resolve_output_path(output, input_file, format)

        if output_path
          File.write(output_path, formatted + "\n")
          puts "Written: #{output_path}"
        else
          puts formatted
        end
      end

      # Resolves the output file path from the --output option value.
      #   nil    → no --output flag; return nil (print to stdout)
      #   ''     → --output with no value; derive from input_file + format
      #   other  → explicit path; expand and use as-is
      def resolve_output_path(output, input_file, format)
        return nil if output.nil?

        if output.empty?
          file_ext = format == 'json' ? '.json' : '.rb'
          dir      = File.dirname(input_file)
          base     = File.basename(input_file, '.*')
          File.join(dir, "#{base}.schema#{file_ext}")
        else
          File.expand_path(output)
        end
      end

      # ── API call ──────────────────────────────────────────────────────────

      def fetch_schema(input_file, hostname, api_token, col_sep:, debug:)
        ext    = File.extname(input_file).delete_prefix('.')  # 'json' or 'csv'
        url    = "https://#{hostname}#{API_GENERATE_SCHEMA_PATH}/#{ext}"
        sample = File.read(input_file)
        sample = wrap_if_array(sample) if ext == 'json'

        payload = { sample: sample }
        payload[:col_sep] = col_sep if ext == 'csv'

        if debug
          warn "[schema] url:     #{url}"
          warn "[schema] col_sep: #{col_sep}" if ext == 'csv'
        end

        response = RestClient.post(
          url,
          payload.to_json,
          content_type:    :json,
          accept:          :json,
          'Authorization' => "Bearer #{api_token}"
        )
        JSON.parse(response.body)
      rescue RestClient::ExceptionWithResponse => e
        msg = begin
                JSON.parse(e.response.body)['message']
              rescue StandardError
                e.message
              end
        Wisco::TerminalOutput.emit_error("Error generating schema: #{msg}")
        exit 1
      rescue StandardError => e
        Wisco::TerminalOutput.emit_error("Error generating schema: #{e.message}")
        exit 1
      end

      # If the JSON content is a top-level array, wrap it in {"input": [...]}
      # so the Workato API accepts it (it requires a top-level object).
      # Returns the (possibly modified) JSON string; never modifies the source file.
      def wrap_if_array(json_content)
        parsed = JSON.parse(json_content)
        return json_content unless parsed.is_a?(Array)

        Wisco::TerminalOutput.emit_info('[INFO] Input JSON is a top-level array.')
        Wisco::TerminalOutput.emit_info('[INFO] Wrapping in {"input": [...]} for Workato API compatibility.')
        JSON.generate({ 'input' => parsed })
      rescue JSON::ParseError
        json_content  # unparseable — send as-is and let the API report the error
      end

      # ── JSON output ───────────────────────────────────────────────────────

      def format_json(schema)
        JSON.pretty_generate(schema)
      end

      # ── Ruby output ───────────────────────────────────────────────────────

      # Renders the top-level schema array as a Ruby literal.
      def format_ruby(schema, style:)
        indent = 4
        items  = schema.map { |field| format_field(field, indent, style) }
        inner  = items.map { |item| "#{' ' * indent}#{item}" }.join(",\n")
        "[\n#{inner}\n]"
      end

      # Renders a single field hash. Recursively handles nested `properties`.
      def format_field(field, base_indent, style)
        # Reorder keys: KEY_ORDER first, then any extras; pull properties out separately
        ordered = KEY_ORDER.select { |k| field.key?(k) }
        extras  = field.keys - KEY_ORDER - ['properties']
        pairs   = (ordered + extras).map { |k| [k, field[k]] }
        props   = field['properties']

        cont_indent = base_indent + 2  # continuation indent (aligns keys after "{ ")
        prop_indent = base_indent + 4  # properties array indent

        if style == :single_line
          kv_str = pairs.map { |k, v| "#{k}: #{ruby_scalar(k, v)}" }.join(', ')

          if props
            prop_lines = format_ruby_array(props, prop_indent, style)
            "{ #{kv_str}, properties:\n#{prop_lines}\n#{' ' * base_indent}}"
          else
            "{ #{kv_str}}"
          end
        else
          # multi_line: first pair on same line as {, rest on new lines
          kv_lines = pairs.map { |k, v| "#{k}: #{ruby_scalar(k, v)}" }
          first    = kv_lines.shift

          if kv_lines.empty? && !props
            # Single pair, no properties
            "{ #{first}}"
          elsif props
            rest      = kv_lines.map { |l| "#{' ' * cont_indent}#{l}" }
            prop_line = "#{' ' * cont_indent}properties:"
            prop_lines = format_ruby_array(props, prop_indent, style)
            parts = ["{ #{first}"] + rest + [prop_line]
            "#{parts.join(",\n")}\n#{prop_lines}\n#{' ' * base_indent}}"
          else
            rest  = kv_lines.map { |l| "#{' ' * cont_indent}#{l}" }
            parts = ["{ #{first}"] + rest
            "#{parts.join(",\n")}}"
          end
        end
      end

      # Renders a properties array (a list of nested fields) at the given indent.
      # The opening/closing brackets sit at `indent` spaces; items are indented
      # a further 4 spaces inside the brackets.
      def format_ruby_array(fields, indent, style)
        item_indent = indent + 4
        items = fields.map { |f| format_field(f, item_indent, style) }
        inner = items.map { |item| "#{' ' * item_indent}#{item}" }.join(",\n")
        "#{' ' * indent}[\n#{inner}\n#{' ' * indent}]"
      end

      # Returns the Ruby literal string for a scalar value.
      def ruby_scalar(key, value)
        if SYMBOL_VALUE_KEYS.include?(key) && value.is_a?(String)
          ":#{value}"
        elsif value.is_a?(String)
          "'#{value.gsub('\\', '\\\\\\\\').gsub("'", "\\\\'")}'"
        elsif value.nil?
          'nil'
        elsif value == true || value == false
          value.to_s
        elsif value.is_a?(Numeric)
          value.to_s
        else
          value.inspect
        end
      end
    end
  end
end
