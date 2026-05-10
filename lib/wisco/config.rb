module Wisco
  module Config
    module_function

    # Ensures workato_developer_api hostname and api_token are present in config.
    # Prompts the user for any missing values and saves the updated config.
    def ensure_api_config(config, config_path)
      api_cfg = config['workato_developer_api'] ||= {}

      if api_cfg['hostname'].nil? || api_cfg['hostname'].strip.empty?
        print 'Workato API hostname not configured. Enter hostname (e.g. app.au.workato.com): '
        api_cfg['hostname'] = $stdin.gets.strip
      end

      if api_cfg['api_token'].nil? || api_cfg['api_token'].strip.empty?
        print 'Workato API token not configured. Enter your API token: '
        api_cfg['api_token'] = $stdin.gets.strip
      end

      save_config(config_path, config)
      config
    end

    def load_config(path)
      return {} unless File.exist?(path)

      begin
        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        warn "Warning: Existing #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME} contains invalid JSON (#{e.message})."
        warn '         Connector section will be overwritten; other content may be lost.'
        {}
      end
    end

    def save_config(path, config)
      File.write(path, JSON.pretty_generate(config) + "\n")
    rescue SystemCallError => e
      warn "Error: Could not write #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME}: #{e.message}"
      exit 1
    end
  end
end
