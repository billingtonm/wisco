require 'erb'
require 'fileutils'
require_relative '../config'
require_relative '../connector'
require_relative '../profile'

module Wisco
  module Commands
    module Init
      module_function

      def run(target_dir, profile: nil)
        target_dir = File.expand_path(target_dir)

        unless Dir.exist?(target_dir)
          warn "Error: Directory not found: #{target_dir}"
          exit 1
        end

        puts "Searching for connector in #{target_dir}..."

        connector_file = Wisco::Connector.detect_connector(target_dir)

        if connector_file.nil?
          warn "Error: No valid Workato connector file found in #{target_dir}"
          exit 1
        end

        puts "Found connector: #{connector_file}"

        wisco_dir   = File.join(target_dir, Wisco::WISCO_DIR)
        FileUtils.mkdir_p(wisco_dir)

        config_path = Wisco.config_path(target_dir)
        config      = Wisco::Config.load_config(config_path)

        config['connector'] ||= {}
        config['connector']['path'] = target_dir
        config['connector']['file'] = connector_file

        prompt_hostname(config, profile: profile)

        Wisco::Config.save_config(config_path, config)
        puts "Config written to #{config_path}"

        update_gitignore(target_dir)
        ensure_gemfile(target_dir)
        deploy_github_workflow(target_dir, connector_file, config)
      end

      def prompt_hostname(config, profile: nil)
        api_cfg = config['workato_developer_api'] ||= {}

        # --profile flag: skip all prompts and attach the named profile
        if profile
          unless Wisco::Profiles.exists?(profile)
            Wisco::TerminalOutput.emit_error("Error: Profile \"#{profile}\" not found in #{Wisco::Profiles.profiles_path}.")
            Wisco::TerminalOutput.emit_error("       Run 'wisco profile list' to see available profiles.")
            exit 1
          end
          api_cfg.delete('hostname')
          api_cfg.delete('api_token')
          api_cfg['profile'] = profile
          puts "Using profile: #{profile}"
          return
        end

        # If profiles exist, offer them alongside "enter manually"
        existing_profiles = Wisco::Profiles.all
        unless existing_profiles.empty?
          current_profile = api_cfg['profile'].to_s.strip
          current_host    = api_cfg['hostname'].to_s.strip

          if !current_profile.empty?
            puts "Current Workato profile: #{current_profile}"
            print 'Keep this? (y/n): '
            return if $stdin.gets.strip.downcase == 'y'
          elsif !current_host.empty?
            puts "Current Workato hostname: #{current_host} (inline credentials)"
            print 'Keep this? (y/n): '
            return if $stdin.gets.strip.downcase == 'y'
          end

          puts 'Workato API credentials'
          name_width = existing_profiles.keys.map(&:length).max
          existing_profiles.each_with_index do |(prof_name, p), i|
            puts "  #{i + 1}. #{prof_name.ljust(name_width)}  (#{p['hostname']})"
          end
          manual_index = existing_profiles.size + 1
          puts "  #{manual_index}. Enter credentials manually"
          loop do
            print "Select an option (1-#{manual_index}): "
            input = $stdin.gets.strip
            index = input.to_i
            if index >= 1 && index < manual_index
              chosen = existing_profiles.keys[index - 1]
              api_cfg.delete('hostname')
              api_cfg.delete('api_token')
              api_cfg['profile'] = chosen
              puts "Using profile: #{chosen}"
              return
            elsif index == manual_index
              break # fall through to manual hostname prompt below
            else
              warn "Invalid selection. Please enter a number between 1 and #{manual_index}."
            end
          end
        else
          # No profiles — check for existing inline hostname
          current = api_cfg['hostname']
          if current && !current.strip.empty?
            puts "Current Workato hostname: #{current}"
            print 'Keep this? (y/n): '
            return if $stdin.gets.strip.downcase == 'y'
          end
        end

        # Manual hostname selection
        hostname = Wisco::Profiles.prompt_hostname_selection
        api_cfg.delete('profile')
        api_cfg['hostname'] = hostname
        puts "Hostname set to: #{hostname}"
      end

      def update_gitignore(target_dir)
        gitignore_path = File.join(target_dir, '.gitignore')
        entry          = "#{Wisco::WISCO_DIR}/"

        if File.exist?(gitignore_path)
          content = File.read(gitignore_path)
          if content.include?(entry)
            puts ".gitignore already contains '#{entry}' — no changes made."
          else
            File.open(gitignore_path, 'a') { |f| f.puts entry }
            puts "Added '#{entry}' to .gitignore"
          end
        else
          asset_path = File.join(__dir__, '..', 'assets', '.gitignore')
          FileUtils.cp(asset_path, gitignore_path)
          puts "Created .gitignore from template"
        end
      end

      def ensure_gemfile(target_dir)
        gemfile_path = File.join(target_dir, 'Gemfile')

        if File.exist?(gemfile_path)
          puts 'Gemfile already exists — no changes made.'
          return
        end

        asset_path = File.join(__dir__, '..', 'assets', 'Gemfile')
        FileUtils.cp(asset_path, gemfile_path)
        Wisco::TerminalOutput.emit_info('[INFO] Created Gemfile from template')
        Wisco::TerminalOutput.emit_info("[INFO] Run 'bundle install' to install dependencies.")
      end

      def deploy_github_workflow(target_dir, connector_file, config)
        output_path = File.join(target_dir, '.github', 'workflows', 'deploy.yml')

        if File.exist?(output_path)
          print '.github/workflows/deploy.yml already exists. Overwrite? (y/n): '
          unless $stdin.gets.strip.downcase == 'y'
            puts 'Skipped: .github/workflows/deploy.yml'
            return
          end
        end

        api_cfg  = config['workato_developer_api'] || {}
        hostname = if api_cfg['profile'].to_s.strip != ''
                     Wisco::Profiles.get(api_cfg['profile'])&.dig('hostname')
                   else
                     api_cfg['hostname']
                   end
        workato_base_url = "https://#{hostname}"
        connector_name   = connector_file

        template_path = File.join(__dir__, '..', 'assets', '.github', 'workflows', 'deploy.yml.erb')
        rendered      = ERB.new(File.read(template_path)).result(binding)

        FileUtils.mkdir_p(File.dirname(output_path))
        File.write(output_path, rendered)
        puts 'Created .github/workflows/deploy.yml'
      end
    end
  end
end
