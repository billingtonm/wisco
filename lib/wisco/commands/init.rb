require 'fileutils'
require_relative '../config'
require_relative '../connector'

module Wisco
  module Commands
    module Init
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

        Wisco::Config.save_config(config_path, config)
        puts "Config written to #{config_path}"

        update_gitignore(target_dir)
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
          puts "Note: No .gitignore found — consider adding '#{entry}' manually."
        end
      end
    end
  end
end
