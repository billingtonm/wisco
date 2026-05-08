module Wisco
  module Config
    module_function

    def load_config(path)
      return {} unless File.exist?(path)

      begin
        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        warn "Warning: Existing #{Wisco::CONFIG_FILENAME} contains invalid JSON (#{e.message})."
        warn '         Connector section will be overwritten; other content may be lost.'
        {}
      end
    end

    def save_config(path, config)
      File.write(path, JSON.pretty_generate(config) + "\n")
    rescue SystemCallError => e
      warn "Error: Could not write #{Wisco::CONFIG_FILENAME}: #{e.message}"
      exit 1
    end
  end
end
