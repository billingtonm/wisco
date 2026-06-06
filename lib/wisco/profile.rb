require 'yaml'
require 'fileutils'
require 'io/console'

module Wisco
  module Profiles
    PROFILES_DIR      = File.join(Dir.home, '.wisco').freeze
    PROFILES_FILENAME = 'profiles.yaml'.freeze

    HOSTNAMES = [
      { region: 'US Data Center', hostname: 'www.workato.com'    },
      { region: 'EU Data Center', hostname: 'app.eu.workato.com' },
      { region: 'JP Data Center', hostname: 'app.jp.workato.com' },
      { region: 'SG Data Center', hostname: 'app.sg.workato.com' },
      { region: 'AU Data Center', hostname: 'app.au.workato.com' },
      { region: 'IL Data Center', hostname: 'app.il.workato.com' },
    ].freeze

    DATACENTER_NAMES = {
      'www.workato.com'    => 'us',
      'app.eu.workato.com' => 'eu',
      'app.jp.workato.com' => 'jp',
      'app.sg.workato.com' => 'sg',
      'app.au.workato.com' => 'au',
      'app.il.workato.com' => 'il',
    }.freeze

    module_function

    def profiles_path
      File.join(PROFILES_DIR, PROFILES_FILENAME)
    end

    def load_profiles
      return {} unless File.exist?(profiles_path)

      YAML.safe_load(File.read(profiles_path)) || {}
    rescue Psych::SyntaxError => e
      Wisco::TerminalOutput.emit_error("Error: Could not parse #{profiles_path}: #{e.message}")
      exit 1
    end

    def save_profiles(data)
      FileUtils.mkdir_p(PROFILES_DIR)
      File.write(profiles_path, YAML.dump(data))
    rescue SystemCallError => e
      Wisco::TerminalOutput.emit_error("Error: Could not write #{profiles_path}: #{e.message}")
      exit 1
    end

    def all
      load_profiles.dig('workato_developer_api') || {}
    end

    def get(name)
      all[name]
    end

    def set(name, hostname, api_token)
      data = load_profiles
      data['workato_developer_api'] ||= {}
      data['workato_developer_api'][name] = { 'hostname' => hostname, 'api_token' => api_token }
      save_profiles(data)
    end

    def delete(name)
      data = load_profiles
      data['workato_developer_api']&.delete(name)
      save_profiles(data)
    end

    def exists?(name)
      !get(name).nil?
    end

    def find_duplicate(hostname, api_token)
      all.find { |_n, p| p['hostname'] == hostname && p['api_token'] == api_token }&.first
    end

    def suggest_name(hostname)
      DATACENTER_NAMES[hostname]
    end

    def mask_token(token)
      return '****' if token.nil? || token.length <= 4

      "****#{token[-4..]}"
    end

    def prompt_token(prompt_text = 'API token (input hidden): ')
      print prompt_text
      token = $stdin.noecho(&:gets).strip
      puts
      token
    rescue Errno::ENOTTY
      # stdin is not a tty (e.g. piped input) — read plainly
      print prompt_text
      $stdin.gets.strip
    end

    def prompt_hostname_selection(allow_skip: false)
      puts 'Select your Workato instance:'
      HOSTNAMES.each_with_index do |entry, i|
        puts "  #{i + 1}. #{entry[:hostname]}  (#{entry[:region]})"
      end
      skip_hint = allow_skip ? ', or Enter to keep current' : ''
      loop do
        print "Enter number (1-#{HOSTNAMES.size})#{skip_hint}: "
        input = $stdin.gets.strip
        return nil if allow_skip && input.empty?

        index = input.to_i
        if index >= 1 && index <= HOSTNAMES.size
          return HOSTNAMES[index - 1][:hostname]
        end

        warn "Invalid selection. Please enter a number between 1 and #{HOSTNAMES.size}."
      end
    end

    def prompt_name(suggestion: nil)
      if suggestion
        print "Profile name [#{suggestion}]: "
        input = $stdin.gets.strip
        input.empty? ? suggestion : input
      else
        loop do
          print 'Profile name: '
          input = $stdin.gets.strip
          return input unless input.empty?

          warn 'Name cannot be blank.'
        end
      end
    end
  end
end
