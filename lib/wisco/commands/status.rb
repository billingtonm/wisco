require 'json'
require_relative '../config'
require_relative '../connector'
require_relative '../profile'
require_relative '../version'

module Wisco
  module Commands
    module Status
      module_function

      def run(target_dir)
        target_dir  = File.expand_path(target_dir)
        config_path = Wisco.config_path(target_dir)

        unless File.exist?(config_path)
          puts JSON.pretty_generate(uninitialised_payload)
          return
        end

        config         = Wisco::Config.load_config(config_path)
        connector_path = config.dig('connector', 'path')
        connector_file = config.dig('connector', 'file')

        if connector_path.nil? || connector_file.nil?
          puts JSON.pretty_generate(uninitialised_payload)
          return
        end

        profile_name = config.dig('workato_developer_api', 'profile').to_s
        profile_name = nil if profile_name.empty?
        hostname     = resolve_hostname(profile_name, config)

        full_connector_path = File.join(connector_path, connector_file)
        connector_info      = load_connector_info(full_connector_path, target_dir)
        credentials         = check_credentials(connector_path)

        payload = {
          'wisco_version' => Wisco::VERSION,
          'initialized'   => true,
          'config_path'   => config_path,
          'profile'       => { 'name' => profile_name },
          'hostname'      => hostname,
          'connection'    => config['connection'],
          'connector'     => {
            'path'  => full_connector_path,
            'valid' => connector_info[:valid],
            'title' => connector_info[:title],
            'error' => connector_info[:error]
          },
          'credentials'   => credentials
        }

        puts JSON.pretty_generate(payload)
      end

      def uninitialised_payload
        {
          'wisco_version' => Wisco::VERSION,
          'initialized'   => false,
          'config_path'   => nil,
          'profile'       => nil,
          'hostname'      => nil,
          'connection'    => nil,
          'connector'     => nil,
          'credentials'   => nil
        }
      end

      def resolve_hostname(profile_name, config)
        if profile_name
          profile = Wisco::Profiles.get(profile_name)
          profile&.dig('hostname')
        else
          config.dig('workato_developer_api', 'hostname')
        end
      end

      def load_connector_info(full_path, target_dir)
        unless File.exist?(full_path)
          return { valid: false, title: nil, error: "Connector file not found: #{full_path}" }
        end

        begin
          connector = Wisco::Connector.load_connector_from_config(target_dir)
          { valid: true, title: connector[:title]&.to_s, error: nil }
        rescue StandardError => e
          { valid: false, title: nil, error: e.message.strip }
        end
      end

      def check_credentials(connector_path)
        plaintext = File.exist?(File.join(connector_path, 'settings.yaml'))
        encrypted = File.exist?(File.join(connector_path, 'settings.yaml.enc'))
        present   = plaintext || encrypted

        {
          'present'   => present,
          'encrypted' => present && !plaintext
        }
      end
    end
  end
end
