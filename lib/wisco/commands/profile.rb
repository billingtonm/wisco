require_relative '../profile'
require_relative '../config'
require_relative '../terminal_output'

module Wisco
  module Commands
    class Profile < Thor
      def self.exit_on_failure?
        true
      end

      desc 'add [NAME]', 'Create a new connection profile'
      long_desc <<~DESC
        Prompts for hostname and API token and saves a named profile in ~/.wisco/profiles.yaml.
        If NAME is omitted, a name is suggested based on the selected datacenter.
      DESC
      def add(name = nil)
        hostname = Wisco::Profiles.prompt_hostname_selection
        puts "Hostname: #{hostname}"

        api_token = Wisco::Profiles.prompt_token('API token (input hidden): ')

        if name.nil?
          suggestion = Wisco::Profiles.suggest_name(hostname)
          name = Wisco::Profiles.prompt_name(suggestion: suggestion)
        end

        if Wisco::Profiles.exists?(name)
          Wisco::TerminalOutput.emit_error("Error: Profile \"#{name}\" already exists. Use 'wisco profile edit #{name}' to update it.")
          exit 1
        end

        Wisco::Profiles.set(name, hostname, api_token)
        puts "Profile \"#{name}\" saved to #{Wisco::Profiles.profiles_path}."
      end

      desc 'list', 'List all connection profiles'
      def list
        profiles = Wisco::Profiles.all
        if profiles.empty?
          puts "No profiles found. Run 'wisco profile add' to create one."
          return
        end
        puts "Profiles (from #{Wisco::Profiles.profiles_path}):\n\n"
        name_width = profiles.keys.map(&:length).max
        profiles.each do |prof_name, p|
          puts "  #{prof_name.ljust(name_width)}  #{p['hostname']}"
        end
      end

      desc 'show NAME', 'Show details of a profile'
      def show(name)
        profile = Wisco::Profiles.get(name)
        if profile.nil?
          Wisco::TerminalOutput.emit_error("Error: Profile \"#{name}\" not found.")
          Wisco::TerminalOutput.emit_error("       Run 'wisco profile list' to see available profiles.")
          exit 1
        end
        puts "Profile: #{name}"
        puts "  hostname:  #{profile['hostname']}"
        puts "  api_token: #{Wisco::Profiles.mask_token(profile['api_token'])}"
      end

      desc 'edit NAME', 'Update the hostname and/or API token for a profile'
      long_desc 'Re-prompts for hostname and API token. Press Enter to keep the current value.'
      def edit(name)
        profile = Wisco::Profiles.get(name)
        if profile.nil?
          Wisco::TerminalOutput.emit_error("Error: Profile \"#{name}\" not found.")
          Wisco::TerminalOutput.emit_error("       Run 'wisco profile list' to see available profiles.")
          exit 1
        end

        puts "Editing profile \"#{name}\":"
        puts "  Current hostname:  #{profile['hostname']}"
        puts "  Current api_token: #{Wisco::Profiles.mask_token(profile['api_token'])}"
        puts

        selected = Wisco::Profiles.prompt_hostname_selection(allow_skip: true)
        hostname = selected || profile['hostname']
        puts "Hostname: #{hostname}"

        raw = Wisco::Profiles.prompt_token('New API token (input hidden, Enter to keep current): ')
        api_token = raw.empty? ? profile['api_token'] : raw

        Wisco::Profiles.set(name, hostname, api_token)
        puts "Profile \"#{name}\" updated."
      end

      desc 'remove NAME', 'Remove a connection profile'
      def remove(name)
        unless Wisco::Profiles.exists?(name)
          Wisco::TerminalOutput.emit_error("Error: Profile \"#{name}\" not found.")
          exit 1
        end
        print "Remove profile \"#{name}\"? (y/n): "
        unless $stdin.gets.strip.downcase == 'y'
          puts 'Aborted.'
          return
        end
        Wisco::Profiles.delete(name)
        puts "Profile \"#{name}\" removed."
      end

      desc 'use NAME', 'Attach a profile to the current connector project'
      def use(name)
        unless Wisco::Profiles.exists?(name)
          Wisco::TerminalOutput.emit_error("Error: Profile \"#{name}\" not found in #{Wisco::Profiles.profiles_path}.")
          Wisco::TerminalOutput.emit_error("       Run 'wisco profile list' to see available profiles.")
          exit 1
        end

        config_path = Wisco.config_path(Dir.pwd)
        unless File.exist?(config_path)
          Wisco::TerminalOutput.emit_error("Error: No #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME} found in #{Dir.pwd}.")
          Wisco::TerminalOutput.emit_error("       Run 'wisco init' first.")
          exit 1
        end

        config  = Wisco::Config.load_config(config_path)
        api_cfg = config['workato_developer_api'] ||= {}
        has_inline = !api_cfg['hostname'].to_s.strip.empty? || !api_cfg['api_token'].to_s.strip.empty?

        if has_inline
          print "This project has inline credentials configured.\nReplace with a reference to profile \"#{name}\"? (y/n): "
          unless $stdin.gets.strip.downcase == 'y'
            puts 'Aborted.'
            return
          end
          api_cfg.delete('hostname')
          api_cfg.delete('api_token')
        end

        api_cfg['profile'] = name
        Wisco::Config.save_config(config_path, config)
        puts "Project config updated to use profile \"#{name}\"."
      end

      desc 'extract [NAME]', "Save this project's inline credentials as a named profile"
      long_desc <<~DESC
        Reads the inline hostname and api_token from this project's .wisco/config.json,
        saves them as a named profile in ~/.wisco/profiles.yaml, then updates config.json
        to reference the profile instead of storing inline credentials.

        If NAME is omitted, a name is suggested based on the project's configured hostname.
      DESC
      def extract(name = nil)
        config_path = Wisco.config_path(Dir.pwd)
        unless File.exist?(config_path)
          Wisco::TerminalOutput.emit_error("Error: No #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME} found in #{Dir.pwd}.")
          Wisco::TerminalOutput.emit_error("       Run 'wisco init' first.")
          exit 1
        end

        config    = Wisco::Config.load_config(config_path)
        api_cfg   = config['workato_developer_api'] || {}
        hostname  = api_cfg['hostname'].to_s.strip
        api_token = api_cfg['api_token'].to_s.strip

        if hostname.empty? || api_token.empty?
          Wisco::TerminalOutput.emit_error('Error: This project does not have inline credentials to extract.')
          Wisco::TerminalOutput.emit_error("       Use 'wisco profile use <name>' to attach an existing profile.")
          exit 1
        end

        duplicate = Wisco::Profiles.find_duplicate(hostname, api_token)
        if duplicate
          puts "A profile with these credentials already exists: #{duplicate} (#{hostname})"
          print 'Reference existing profile instead of creating a new one? (y/n): '
          if $stdin.gets.strip.downcase == 'y'
            api_cfg.delete('hostname')
            api_cfg.delete('api_token')
            api_cfg['profile'] = duplicate
            Wisco::Config.save_config(config_path, config)
            puts "Project config updated to reference profile \"#{duplicate}\"."
            return
          end
        end

        if name.nil?
          suggestion = Wisco::Profiles.suggest_name(hostname)
          name = Wisco::Profiles.prompt_name(suggestion: suggestion)
        end

        if Wisco::Profiles.exists?(name)
          Wisco::TerminalOutput.emit_error("Error: Profile \"#{name}\" already exists. Choose a different name or use 'wisco profile edit #{name}'.")
          exit 1
        end

        Wisco::Profiles.set(name, hostname, api_token)
        puts "Profile \"#{name}\" created in #{Wisco::Profiles.profiles_path}."

        api_cfg.delete('hostname')
        api_cfg.delete('api_token')
        api_cfg['profile'] = name
        Wisco::Config.save_config(config_path, config)
        puts "Project config updated to reference profile \"#{name}\"."
      end

      desc 'current', 'Show which profile or credentials this project is using'
      def current
        config_path = Wisco.config_path(Dir.pwd)
        unless File.exist?(config_path)
          Wisco::TerminalOutput.emit_error("Error: No #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME} found in #{Dir.pwd}.")
          Wisco::TerminalOutput.emit_error("       Run 'wisco init' first.")
          exit 1
        end

        config    = Wisco::Config.load_config(config_path)
        api_cfg   = config['workato_developer_api'] || {}
        prof_name = api_cfg['profile'].to_s.strip
        hostname  = api_cfg['hostname'].to_s.strip
        api_token = api_cfg['api_token'].to_s.strip

        if !prof_name.empty?
          profile = Wisco::Profiles.get(prof_name)
          if profile.nil?
            Wisco::TerminalOutput.emit_error("This project references profile \"#{prof_name}\" which does not exist.")
            Wisco::TerminalOutput.emit_error("Run 'wisco profile list' to see available profiles.")
            exit 1
          end
          puts "This project uses profile: #{prof_name}"
          puts "  hostname:  #{profile['hostname']}"
          puts "  api_token: #{Wisco::Profiles.mask_token(profile['api_token'])}"
        elsif !hostname.empty?
          puts 'This project uses inline credentials (no profile).'
          puts "  hostname:  #{hostname}"
          puts "  api_token: #{Wisco::Profiles.mask_token(api_token)}"
        else
          puts 'This project has no Workato API credentials configured.'
          puts "Run 'wisco init' or 'wisco profile use <name>' to configure."
        end
      end
    end
  end
end
