require 'json'
require_relative '../config'
require_relative '../connector'
require_relative '../settings_store'
require_relative '../terminal_output'

module Wisco
  module Commands
    class Settings < Thor
      def self.exit_on_failure?
        true
      end

      desc 'list', 'List connection sets in the settings file'
      option :format, type: :string, enum: %w[json], desc: 'Machine-readable output (json = array of set names)'
      def list
        store = settings_store
        data  = read_settings!(store)
        names = Wisco::SettingsStore.set_names(data)

        if options[:format] == 'json'
          puts JSON.generate(names)
          return
        end

        case Wisco::SettingsStore.detect_structure(data)
        when :nested, :mixed
          active = active_connection
          puts "Connection sets (#{store.filename}):\n\n"
          width = names.map(&:length).max || 0
          names.each do |n|
            marker = n == active ? '*' : ' '
            puts "  #{marker} #{n.ljust(width)}"
          end
          if active && !active.empty?
            puts
            puts "Active connection (from #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME}): #{active}"
          end
        when :flat
          puts "#{store.filename} contains a single, unnamed connection set."
          puts "No named connection sets are defined. Use 'wisco settings add <name>' to create named sets."
        when :none
          puts "No settings file found in #{store.connector_path}."
          puts "Run 'wisco settings add <name>' to create one, or 'workato edit' to create an encrypted file."
        end
      end

      desc 'set CONNECTION', "Set the project's active connection set"
      def set(connection)
        store = settings_store
        names = begin
          Wisco::SettingsStore.set_names(store.read_all)
        rescue Wisco::SettingsStore::MissingKeyError
          nil
        end

        if names.nil?
          Wisco::TerminalOutput.emit_warning("Warning: could not read #{store.filename} to validate (no master key).")
          Wisco::TerminalOutput.emit_warning('         Config updated anyway.')
        elsif !names.include?(connection)
          Wisco::TerminalOutput.emit_warning("Warning: \"#{connection}\" is not currently defined in #{store.filename}.")
          Wisco::TerminalOutput.emit_warning("         Defined sets: #{names.empty? ? '(none)' : names.join(', ')}")
          Wisco::TerminalOutput.emit_warning("         Config updated anyway. Run 'wisco settings add #{connection}' to create it.")
        end

        cfg = config
        cfg['connection'] = connection
        Wisco::Config.save_config(config_path, cfg)
        puts "Active connection set to \"#{connection}\" in #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME}."
      end

      desc 'add CONNECTION', 'Scaffold a new connection set from connector.connection.fields'
      long_desc <<~DESC
        Reads connection.fields from the connector and writes a new named connection
        set with those field names and blank values. Fill the values in afterwards
        with 'workato edit'. If the settings file currently holds a single unnamed
        (flat) connection set, you are prompted to name it so the file can be
        converted to the named (nested) format.
      DESC
      def add(connection)
        field_names = connection_field_names!
        if field_names.empty?
          Wisco::TerminalOutput.emit_error('Error: The connector defines no connection.fields to scaffold.')
          exit 1
        end
        new_set = field_names.each_with_object({}) { |n, h| h[n] = '' }

        store = settings_store
        data  = read_settings!(store)
        structure = Wisco::SettingsStore.detect_structure(data)

        if Wisco::SettingsStore.set_names(data).include?(connection)
          Wisco::TerminalOutput.emit_error("Error: Connection set \"#{connection}\" already exists in #{store.filename}.")
          Wisco::TerminalOutput.emit_error("       Use 'wisco settings show #{connection}' to view it, or edit it with 'workato edit'.")
          exit 1
        end

        target =
          case structure
          when :nested
            data.merge(connection => new_set)
          when :none
            { connection => new_set }
          when :flat
            migrate_flat(data, store).merge(connection => new_set)
          when :mixed
            Wisco::TerminalOutput.emit_error("Error: #{store.filename} mixes flat keys and named sets; resolve it with 'workato edit' before adding.")
            exit 1
          end

        # A brand-new file is written plaintext; existing files keep their form.
        encrypted = structure != :none && store.encrypted?
        written   = encrypted ? Wisco::SettingsStore::ENCRYPTED_FILENAME : Wisco::SettingsStore::PLAINTEXT_FILENAME
        store.write_all(target, encrypted: encrypted)

        puts "Added connection set \"#{connection}\" to #{written} with #{field_names.length} blank field(s):"
        puts "  #{field_names.join(', ')}"
        puts "Fill in the values with 'workato edit', then run 'wisco settings set #{connection}'."
      end

      desc 'show [CONNECTION]', "Show a connection set's field values (passwords masked)"
      option :format, type: :string, enum: %w[json], desc: 'Machine-readable output (json = connection fields with current values)'
      def show(connection = nil)
        store = settings_store
        data  = read_settings!(store)

        name, set =
          case Wisco::SettingsStore.detect_structure(data)
          when :none
            Wisco::TerminalOutput.emit_error("Error: No settings file found in #{store.connector_path}. Nothing to show.")
            exit 1
          when :flat
            if connection
              Wisco::TerminalOutput.emit_error("Error: #{store.filename} has a single unnamed connection set; there is no named set \"#{connection}\".")
              exit 1
            end
            [nil, data]
          when :nested, :mixed
            names = Wisco::SettingsStore.set_names(data)
            if connection.nil?
              Wisco::TerminalOutput.emit_warning('Warning: This settings file has multiple connection sets; specify which one to show.')
              Wisco::TerminalOutput.emit_warning("         Defined sets: #{names.join(', ')}")
              return
            end
            unless names.include?(connection)
              Wisco::TerminalOutput.emit_error("Error: Connection set \"#{connection}\" not found in #{store.filename}.")
              Wisco::TerminalOutput.emit_error("       Defined sets: #{names.join(', ')}")
              exit 1
            end
            [connection, data[connection]]
          end

        if options[:format] == 'json'
          render_set_json(set)
        else
          render_set(name, set, store)
        end
      end

      desc 'current', 'Show which connection set the project points at'
      def current
        active = active_connection.to_s.strip
        store  = settings_store
        data   = begin
          store.read_all
        rescue Wisco::SettingsStore::MissingKeyError
          nil
        end
        names = data ? Wisco::SettingsStore.set_names(data) : []

        if active.empty?
          puts 'This project has no named connection selected (config.json has no "connection" key).'
          puts "The connector will use the single connection set in #{store.filename}."
          return
        end

        puts "This project uses connection set: #{active}"
        if data.nil?
          Wisco::TerminalOutput.emit_warning("  Could not read #{store.filename} to verify (no master key).")
        elsif names.include?(active)
          puts "  Defined in: #{store.filename}  ✓"
        else
          puts "  Not found in #{store.filename}. Run 'wisco settings add #{active}' to create it."
        end
      end

      desc 'fields', 'List the connector connection fields'
      option :format, type: :string, enum: %w[json], desc: 'Machine-readable output (json)'
      def fields
        raw = connection_fields!

        if options[:format] == 'json'
          puts JSON.pretty_generate(raw)
          return
        end

        if raw.empty?
          puts 'Connector defines no connection fields.'
          return
        end

        rows = raw.map do |f|
          [
            field_attr(f, :name).to_s,
            field_attr(f, :label).to_s,
            (field_attr(f, :control_type) || '(default)').to_s,
            field_attr(f, :optional) ? 'no' : 'yes'
          ]
        end

        headers = %w[Name Label Type Required]
        widths  = headers.each_index.map do |i|
          ([headers[i]] + rows.map { |r| r[i] }).map(&:length).max
        end

        puts "Connection fields (from #{connector_file_basename}):\n\n"
        puts "  #{headers.each_with_index.map { |h, i| h.ljust(widths[i]) }.join('  ')}"
        rows.each do |r|
          puts "  #{r.each_with_index.map { |c, i| c.ljust(widths[i]) }.join('  ')}"
        end
      end

      no_commands do
        def target_dir
          Dir.pwd
        end

        def config_path
          Wisco.config_path(target_dir)
        end

        def config
          @config ||= begin
            unless File.exist?(config_path)
              Wisco::TerminalOutput.emit_error("Error: No #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME} found in #{target_dir}.")
              Wisco::TerminalOutput.emit_error("       Run 'wisco init' first.")
              exit 1
            end
            Wisco::Config.load_config(config_path)
          end
        end

        def connector_path
          path = config.dig('connector', 'path')
          if path.nil?
            Wisco::TerminalOutput.emit_error("Error: #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME} is missing connector path. Run 'wisco init' again.")
            exit 1
          end
          path
        end

        def connector_file_basename
          config.dig('connector', 'file') || 'connector.rb'
        end

        def active_connection
          config['connection']
        end

        def settings_store
          Wisco::SettingsStore.new(connector_path)
        end

        # Reads the settings file, converting a missing master key into a clean
        # error+exit (used by commands that cannot proceed without the contents).
        def read_settings!(store)
          store.read_all
        rescue Wisco::SettingsStore::MissingKeyError => e
          Wisco::TerminalOutput.emit_error("Error: #{e.message}")
          exit 1
        end

        # connection.fields array from the connector (symbol-keyed hashes).
        # Exits with the connector's load error if it cannot be loaded.
        def connection_fields!
          connector = Wisco::Connector.load_connector_from_config(target_dir)
          Array(connector.is_a?(Hash) ? connector.dig(:connection, :fields) : nil)
        rescue StandardError => e
          Wisco::TerminalOutput.emit_error("Error: #{e.message.strip}")
          exit 1
        end

        def connection_field_names!
          connection_fields!.map { |f| field_attr(f, :name).to_s }.reject(&:empty?)
        end

        # Password field names for masking. Degrades gracefully (returns []) if
        # the connector cannot be loaded, so `show` still works.
        def password_field_names
          connector = Wisco::Connector.load_connector_from_config(target_dir)
          fields = Array(connector.is_a?(Hash) ? connector.dig(:connection, :fields) : nil)
          fields.select { |f| field_attr(f, :control_type).to_s == 'password' }
                .map { |f| field_attr(f, :name).to_s }
        rescue SystemExit, StandardError
          Wisco::TerminalOutput.emit_warning('Warning: could not load connector to identify password fields; showing all values unmasked.')
          []
        end

        def field_attr(field, key)
          return nil unless field.is_a?(Hash)

          field[key] || field[key.to_s]
        end

        def render_set(name, set, store)
          passwords = password_field_names
          header    = name || '(single/unnamed)'
          puts "Connection set: #{header}   (#{store.filename})\n\n"

          if set.nil? || set.empty?
            puts '  (no fields)'
            return
          end

          width = set.keys.map { |k| k.to_s.length }.max
          set.each do |k, v|
            display =
              if v.to_s.empty?
                '(blank)'
              elsif passwords.include?(k.to_s)
                mask(v.to_s)
              else
                v.to_s
              end
            puts "  #{k.to_s.ljust(width)}  #{display}"
          end
        end

        def mask(value)
          return '****' if value.length <= 4

          "****#{value[-4..]}"
        end

        # Machine-readable form of a connection set: the connector's
        # connection.fields array, each field augmented with a `value` key holding
        # the current stored value (null when the field is unset or blank). Values
        # are unmasked — this output is for tooling, not display.
        def render_set_json(set)
          set ||= {}
          out = connection_fields!.map do |f|
            raw   = set[field_attr(f, :name).to_s]
            value = raw.nil? || raw.to_s.empty? ? nil : raw
            f.merge(value: value)
          end
          puts JSON.pretty_generate(out)
        end

        def migrate_flat(flat_data, store)
          puts "#{store.filename} currently holds a single unnamed connection set."
          puts 'Adding a named set requires converting the file to the named (nested) format.'
          print 'Enter a name for the existing connection set (or press Enter to skip): '
          name = $stdin.gets.to_s.strip
          if name.empty?
            Wisco::TerminalOutput.emit_error('Aborted: mixing flat and named connection sets is not supported.')
            exit 1
          end
          { name => flat_data }
        end
      end
    end
  end
end
