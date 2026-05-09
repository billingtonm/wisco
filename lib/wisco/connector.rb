require_relative 'config'

module Wisco
  module Connector
    module_function

    def detect_connector(dir)
      candidates = candidate_files(dir)

      if candidates.empty?
        warn "  No .rb files found in #{dir}"
        return nil
      end

      candidates.each do |filename|
        puts "  Checking #{filename}..."
        return filename if valid_connector?(File.join(dir, filename))
      end

      nil
    end

    def load_connector_from_config(target_dir)
      target_dir = File.expand_path(target_dir)
      config_path = Wisco.config_path(target_dir)

      unless File.exist?(config_path)
        warn "Error: No #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME} found in #{target_dir}."
        warn "       Run '#{Wisco::CLI_NAME} init' first."
        exit 1
      end

      config = Wisco::Config.load_config(config_path)
      connector_file = config.dig('connector', 'file')
      connector_path = config.dig('connector', 'path')

      if connector_file.nil? || connector_path.nil?
        warn "Error: #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME} is missing connector path/file. Run '#{Wisco::CLI_NAME} init' again."
        exit 1
      end

      full_path = File.join(connector_path, connector_file)
      unless File.exist?(full_path)
        warn "Error: Connector file not found: #{full_path}"
        exit 1
      end

      code = File.read(full_path)
      original_verbose = $VERBOSE
      $VERBOSE = nil
      begin
        result = eval(code) # rubocop:disable Security/Eval
      rescue Exception => e
        raise "\nConnector contains errors:\n#{e.message}"
        warn "Error: Failed to load connector: #{e.message}"
        exit 1
      ensure
        $VERBOSE = original_verbose
      end

      result
    end

    def candidate_files(dir)
      primary = 'connector.rb'
      others = Dir.glob(File.join(dir, '*.rb'))
                  .map { |f| File.basename(f) }
                  .reject { |f| f == primary }
                  .sort

      result = []
      result << primary if File.exist?(File.join(dir, primary))
      result.concat(others)
      result
    end

    def valid_connector?(path)
      code = File.read(path)
      original_verbose = $VERBOSE
      $VERBOSE = nil
      begin
        result = eval(code) # rubocop:disable Security/Eval
        result.is_a?(Hash) && result.key?(:title)
      rescue Exception => e
        false
      ensure
        $VERBOSE = original_verbose
      end
    end
  end
end
