require 'erb'
require 'fileutils'
require_relative '../config'
require_relative '../connector'

module Wisco
  module Commands
    module Init
      HOSTNAMES = [
        { region: 'US Data Center', hostname: 'www.workato.com'    },
        { region: 'EU Data Center', hostname: 'app.eu.workato.com' },
        { region: 'JP Data Center', hostname: 'app.jp.workato.com' },
        { region: 'SG Data Center', hostname: 'app.sg.workato.com' },
        { region: 'AU Data Center', hostname: 'app.au.workato.com' },
        { region: 'IL Data Center', hostname: 'app.il.workato.com' },
      ].freeze

      module_function

      def run(target_dir)
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

        prompt_hostname(config)

        Wisco::Config.save_config(config_path, config)
        puts "Config written to #{config_path}"

        update_gitignore(target_dir)
        ensure_gemfile(target_dir)
        deploy_github_workflow(target_dir, connector_file, config)
      end

      def prompt_hostname(config)
        api_cfg = config['workato_developer_api'] ||= {}
        current = api_cfg['hostname']

        if current && !current.strip.empty?
          puts "Current Workato hostname: #{current}"
          print 'Keep this? (y/n): '
          return if $stdin.gets.strip.downcase == 'y'
        end

        puts 'Select your Workato instance:'
        HOSTNAMES.each_with_index do |entry, i|
          puts "  #{i + 1}. #{entry[:hostname]}  (#{entry[:region]})"
        end

        loop do
          print "Enter number (1-#{HOSTNAMES.size}): "
          input = $stdin.gets.strip
          index = input.to_i
          if index >= 1 && index <= HOSTNAMES.size
            api_cfg['hostname'] = HOSTNAMES[index - 1][:hostname]
            puts "Hostname set to: #{api_cfg['hostname']}"
            return
          end
          warn "Invalid selection. Please enter a number between 1 and #{HOSTNAMES.size}."
        end
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

        hostname         = config.dig('workato_developer_api', 'hostname')
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
