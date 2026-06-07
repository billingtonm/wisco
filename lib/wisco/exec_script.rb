require 'workato/connector/sdk'
require_relative 'terminal_output'

module Wisco
  # Evaluates an `execute_*.rb` script and returns the value of its last
  # expression. The script is eval'd inside a binding that exposes helpers
  # (`call_method`, `call_pick_list`, `connection`) so the script can build
  # dynamic input that varies per run.
  module ExecScript
    SENTINEL_REGEX = /\A\s*#\s*WISCO_SKIP\b/.freeze

    module_function

    # Returns true if the file's first non-blank line is a `# WISCO_SKIP`
    # comment, in which case the script should be skipped by `wisco exec`.
    def sentinel?(path)
      File.foreach(path) do |line|
        stripped = line.strip
        next if stripped.empty?
        return SENTINEL_REGEX.match?(line)
      end
      false
    rescue StandardError
      false
    end

    # Evaluates the script at `script_path` and returns the value of its last
    # expression. Raises StandardError subclasses on:
    #   - syntax / runtime errors in the script
    #   - invalid return value (must be a Hash or Array)
    #
    # `connector_full_path` — absolute path to connector.rb (used to build
    #                          the SDK Connector for helper invocations).
    # `target_dir`          — connector project root (used to find
    #                          settings.yaml(.enc) + master.key).
    # `connection_name`     — connection key inside settings.yaml; defaults to 'default'.
    def evaluate(script_path:, connector_full_path:, target_dir:, connection_name: 'default')
      host   = ScriptHost.new(connector_full_path, target_dir, connection_name)
      source = File.read(script_path)
      result = host.instance_eval(source, script_path, 1)

      unless result.is_a?(Hash) || result.is_a?(Array)
        raise InvalidReturn,
              "Script must return a Hash (for actions/triggers) or Array/Hash (for methods/pick_lists). " \
              "Got: #{result.class}"
      end

      result
    end

    class InvalidReturn < StandardError; end

    # Host object that the script is eval'd against. Exposes the helper API.
    # Defined as a class (not a Module) so `instance_eval` gives the script
    # access to standard top-level Ruby plus our helpers, without polluting
    # Object globally.
    class ScriptHost
      def initialize(connector_full_path, target_dir, connection_name)
        @connector_full_path = connector_full_path
        @target_dir          = target_dir
        @connection_name     = connection_name || 'default'
        @sdk_connector       = nil
        @connection_loaded   = false
        @connection_cached   = nil
        @warned_settings     = false
      end

      # Hash of decrypted settings for the configured connection. Returns {}
      # and emits a one-time warning if settings can't be loaded.
      def connection
        return @connection_cached if @connection_loaded

        @connection_loaded = true
        @connection_cached = load_connection
      end

      # Invoke a connector `methods:` entry. Args are forwarded to the lambda
      # as-is. Returns the lambda's return value.
      #
      # Example:
      #   call_method(:format_timestamp, Time.now)
      def call_method(name, *args)
        proxy = sdk_connector.methods
        unless proxy.respond_to?(name.to_sym)
          raise InvalidReturn, "No methods entry named '#{name}' found in connector."
        end
        proxy.public_send(name.to_sym, *args)
      end

      # Invoke a connector `pick_lists:` entry. `args` is a Hash of named
      # arguments for dependent pick lists. The SDK supplies `connection` to
      # the lambda automatically.
      #
      # Examples:
      #   call_pick_list(:active_customers)
      #   call_pick_list(:customer_orders, customer_id: 123)
      def call_pick_list(name, **args)
        proxy = sdk_connector.pick_lists
        unless proxy.respond_to?(name.to_sym)
          raise InvalidReturn, "No pick_lists entry named '#{name}' found in connector."
        end
        # SDK signature: pick_list_name(settings = nil, args = {})
        # Passing nil for settings tells the SDK to reuse the connector's settings.
        proxy.public_send(name.to_sym, nil, args)
      end

      private

      def sdk_connector
        @sdk_connector ||= Workato::Connector::Sdk::Connector.from_file(@connector_full_path, connection)
      end

      # Tries (in order): settings.yaml.enc + master.key, then settings.yaml.
      # Uses Workato::Connector::Sdk::Settings so encryption is handled by the
      # SDK's own loader (same path it uses for `wisco exec`). Returns {} and
      # warns once on any failure.
      def load_connection
        enc_file  = File.join(@target_dir, 'settings.yaml.enc')
        key_file  = File.join(@target_dir, 'master.key')
        yaml_file = File.join(@target_dir, 'settings.yaml')

        if File.exist?(enc_file) && File.exist?(key_file)
          read_settings(enc_file) do |name|
            Workato::Connector::Sdk::Settings.from_encrypted_file(enc_file, key_file, name)
          end
        elsif File.exist?(yaml_file)
          read_settings(yaml_file) do |name|
            Workato::Connector::Sdk::Settings.from_file(yaml_file, name)
          end
        else
          warn_settings("No settings.yaml or settings.yaml.enc found in #{@target_dir}")
          {}
        end
      end

      # Reads settings using a Settings.from_* loader. Tries with the configured
      # connection name first; if that key isn't present at the top level
      # (KeyError), falls back to loading the whole file as a flat hash.
      def read_settings(path)
        hash = begin
                 yield(@connection_name)
               rescue KeyError
                 yield(nil)
               end
        return {} unless hash.respond_to?(:to_h)

        hash.to_h
      rescue StandardError => e
        warn_settings("Failed to load settings from #{path}: #{e.message}")
        {}
      end

      def warn_settings(msg)
        return if @warned_settings
        @warned_settings = true
        Wisco::TerminalOutput.emit_warning("[WARN] connection helper: #{msg}. Returning {}.")
      end
    end
  end
end
