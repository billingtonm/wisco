require 'yaml'
require 'active_support/encrypted_configuration'
require 'workato/connector/sdk'
require_relative 'terminal_output'

module Wisco
  # Read/write wrapper over the Workato SDK settings file (settings.yaml /
  # settings.yaml.enc) living in a connector directory. Handles encrypted vs
  # plaintext auto-detection, master-key resolution, and flat-vs-nested
  # connection-set detection. See doc-specs/wisco-10-settings.md.
  class SettingsStore
    PLAINTEXT_FILENAME  = 'settings.yaml'.freeze
    ENCRYPTED_FILENAME  = 'settings.yaml.enc'.freeze
    MASTER_KEY_FILENAME = 'master.key'.freeze
    MASTER_KEY_ENV      = 'WORKATO_CONNECTOR_MASTER_KEY'.freeze

    class MissingKeyError < StandardError; end

    attr_reader :connector_path

    def initialize(connector_path)
      @connector_path = File.expand_path(connector_path)
    end

    def plaintext_path
      File.join(@connector_path, PLAINTEXT_FILENAME)
    end

    def encrypted_path
      File.join(@connector_path, ENCRYPTED_FILENAME)
    end

    def master_key_path
      File.join(@connector_path, MASTER_KEY_FILENAME)
    end

    # :encrypted (settings.yaml.enc present), :plaintext (settings.yaml present),
    # or :none. Encrypted takes precedence when both exist.
    def form
      if File.exist?(encrypted_path)
        :encrypted
      elsif File.exist?(plaintext_path)
        :plaintext
      else
        :none
      end
    end

    def encrypted?
      form == :encrypted
    end

    def exist?
      form != :none
    end

    # Basename for user-facing messages; falls back to the plaintext name when
    # no file exists yet (that is the form `add` would create).
    def filename
      encrypted? ? ENCRYPTED_FILENAME : PLAINTEXT_FILENAME
    end

    def master_key_available?
      !ENV[MASTER_KEY_ENV].to_s.strip.empty? || File.exist?(master_key_path)
    end

    # Reads the entire settings file (all sets) as a plain string-keyed Hash.
    # Returns {} when no file exists. Raises MissingKeyError if the file is
    # encrypted and no master key is available.
    def read_all
      case form
      when :none
        {}
      when :plaintext
        parsed = YAML.safe_load(File.read(plaintext_path), permitted_classes: [::Symbol])
        parsed.is_a?(Hash) ? parsed : {}
      when :encrypted
        require_master_key!
        raw = Workato::Connector::Sdk::Settings.from_encrypted_file(encrypted_path, master_key_path)
        raw.respond_to?(:to_hash) ? raw.to_hash : {}
      end
    end

    # Replaces the whole settings file with `data`. When `encrypted:` is true the
    # content is encrypted with the resolved master key; otherwise a plaintext
    # settings.yaml is written. Rewriting wholesale (rather than the SDK's
    # merge-only #update) is what lets `add` migrate a flat file to nested form.
    def write_all(data, encrypted:)
      if encrypted
        require_master_key!
        config = ActiveSupport::EncryptedConfiguration.new(
          config_path:          encrypted_path,
          key_path:             master_key_path,
          env_key:              MASTER_KEY_ENV,
          raise_if_missing_key: true
        )
        config.write(YAML.dump(data))
      else
        File.write(plaintext_path, YAML.dump(data))
      end
    end

    def require_master_key!
      return if master_key_available?

      raise MissingKeyError,
            "#{ENCRYPTED_FILENAME} is encrypted but no master key was found.\n" \
            "       Set #{MASTER_KEY_ENV} or provide a #{MASTER_KEY_FILENAME} file in #{@connector_path}."
    end

    # :none, :flat (all top-level values scalar), :nested (all Hash), or :mixed.
    def self.detect_structure(data)
      return :none if data.nil? || data.empty?

      values = data.values
      if values.all? { |v| v.is_a?(Hash) }
        :nested
      elsif values.none? { |v| v.is_a?(Hash) }
        :flat
      else
        :mixed
      end
    end

    # Names of the named (nested) connection sets — the top-level keys whose
    # value is a Hash. Empty for flat/none files.
    def self.set_names(data)
      return [] if data.nil?

      data.select { |_k, v| v.is_a?(Hash) }.keys
    end
  end
end
