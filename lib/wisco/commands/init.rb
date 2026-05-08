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

        config_path = File.join(target_dir, Wisco::CONFIG_FILENAME)
        config = Wisco::Config.load_config(config_path)

        config['connector'] ||= {}
        config['connector']['path'] = target_dir
        config['connector']['file'] = connector_file

        Wisco::Config.save_config(config_path, config)
        puts "Config written to #{config_path}"
      end
    end
  end
end
