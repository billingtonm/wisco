module Wisco
  module Config
    module_function

    # Ensures workato_developer_api hostname and api_token are available in config.
    # Resolves profile references, handles conflicts, and prompts for missing inline values.
    # When a profile is used, credentials are injected into the in-memory config so all
    # callers can continue to use config.dig('workato_developer_api', 'hostname') etc.
    def ensure_api_config(config, config_path)
      api_cfg     = config['workato_developer_api'] ||= {}
      has_profile = !api_cfg['profile'].to_s.strip.empty?
      has_inline  = !api_cfg['hostname'].to_s.strip.empty? && !api_cfg['api_token'].to_s.strip.empty?

      if has_profile && has_inline
        resolve_profile_conflict(api_cfg, config, config_path)
        has_profile = !api_cfg['profile'].to_s.strip.empty?
      end

      if has_profile
        profile_name = api_cfg['profile']
        profile      = Wisco::Profiles.get(profile_name)
        if profile.nil?
          Wisco::TerminalOutput.emit_error("Error: Profile \"#{profile_name}\" not found in #{Wisco::Profiles.profiles_path}.")
          Wisco::TerminalOutput.emit_error("       Run 'wisco profile list' to see available profiles.")
          exit 1
        end
        api_cfg['hostname']  = profile['hostname']
        api_cfg['api_token'] = profile['api_token']
        return config
      end

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

    def resolve_profile_conflict(api_cfg, config, config_path)
      Wisco::TerminalOutput.emit_warning('Warning: This project has both a profile reference and inline credentials.')
      puts "  Profile:  #{api_cfg['profile']}"
      puts "  Hostname: #{api_cfg['hostname']}"
      puts
      puts 'Which should be kept?'
      puts "  1. Profile reference (\"#{api_cfg['profile']}\")"
      puts '  2. Inline credentials'
      loop do
        print 'Enter 1 or 2: '
        case $stdin.gets.strip
        when '1'
          api_cfg.delete('hostname')
          api_cfg.delete('api_token')
          save_config(config_path, config)
          puts "Inline credentials removed. Using profile \"#{api_cfg['profile']}\"."
          return
        when '2'
          api_cfg.delete('profile')
          save_config(config_path, config)
          puts 'Profile reference removed. Using inline credentials.'
          return
        else
          warn 'Please enter 1 or 2.'
        end
      end
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
