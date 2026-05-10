require 'fileutils'
require 'base64'
require 'json'
require_relative '../config'
require_relative '../connector'
require_relative '../workato_api'

module Wisco
  module Commands
    module Pull
      VALID_WHAT   = %w[all logo code versions meta].freeze
      LOGO_FILENAME = 'logo.png'.freeze
      VERSION_KEYS = %w[latest_version latest_version_note latest_released_version
                        latest_released_version_note latest_shared_version
                        latest_shared_version_note oem_shared_version
                        oem_shared_at recent_released_versions].freeze

      module_function

      def run(target_dir, what:, title:, debug:)
        target_dir  = File.expand_path(target_dir)
        config_path = Wisco.config_path(target_dir)

        unless File.exist?(config_path)
          warn "Error: No #{Wisco::WISCO_DIR}/#{Wisco::CONFIG_FILENAME} found in #{target_dir}."
          warn "       Run '#{Wisco::CLI_NAME} init' first."
          exit 1
        end

        config    = Wisco::Config.load_config(config_path)
        config    = Wisco::Config.ensure_api_config(config, config_path)
        what_list = parse_what(what)
        title   ||= derive_title(target_dir)

        pull_dir = File.join(target_dir, Wisco::WISCO_DIR, 'pull')
        FileUtils.mkdir_p(pull_dir)

        api = Wisco::WorkatoApi.new(
          hostname:  config.dig('workato_developer_api', 'hostname'),
          api_token: config.dig('workato_developer_api', 'api_token'),
          debug:     debug
        )

        datetime = Time.now.localtime.strftime('%Y%m%d_%H%M%S')

        # Step 1: Search
        warn "[pull] Searching for connector: #{title}" if debug
        status, search_data, raw_body = api.search_connector(title: title)
        handle_http_error(status, 'search', title, body: raw_body)

        connector   = extract_single(search_data, title)
        maybe_save_title(connector, config, config_path)
        search_file = File.join(pull_dir, 'meta.json')
        write_json(search_file, search_data)
        puts "Meta:        \t#{search_file}"

        # Logo
        if what_list.include?('logo') || what_list.include?('all')
          connector_root = config.dig('connector', 'path')
          root_logo      = File.join(connector_root, LOGO_FILENAME)
          if File.exist?(root_logo)
            logo_file = save_logo(pull_dir, connector['logo'])
            puts "Logo:        \t#{logo_file}" if logo_file
            puts "               (saved to pull dir — #{LOGO_FILENAME} already exists in connector root)"
          else
            logo_file = save_logo(connector_root, connector['logo'])
            puts "Logo:        \t#{logo_file}" if logo_file
          end
        end

        # Versions
        if what_list.include?('versions') || what_list.include?('all')
          versions_file = save_versions(pull_dir, connector)
          puts "Versions:    \t#{versions_file}"
        end

        # Code
        if what_list.include?('code') || what_list.include?('all')
          warn "[pull] Fetching code for id=#{connector['id']}" if debug
          status, code_data, raw_body = api.get_connector_code(id: connector['id'])
          handle_http_error(status, 'code', connector['id'], body: raw_body)

          rb_file = File.join(pull_dir, "#{connector['name']}.rb")
          File.write(rb_file, code_data.dig('data', 'code').to_s)
          puts "Code:        \t#{rb_file}"
        end
      end

      # ── helpers ──────────────────────────────────────────────────────────

      def derive_title(target_dir)
        connector = Wisco::Connector.load_connector_from_config(target_dir)
        title = connector[:title]
        if title.nil? || title.strip.empty?
          warn "Error: Could not derive connector title from connector file."
          warn "       Use --title to specify it explicitly."
          exit 1
        end
        title
      end

      def parse_what(what_str)
        values  = what_str.to_s.split(',').map(&:strip).map(&:downcase)
        invalid = values - VALID_WHAT
        unless invalid.empty?
          warn "Error: Invalid --what value(s): #{invalid.join(', ')}"
          warn "       Valid values: #{VALID_WHAT.join(', ')}"
          exit 1
        end
        values
      end

      def extract_single(data, title)
        results = case data
                  when Hash  then Array(data['data'] || data)
                  when Array then data
                  else []
                  end

        if results.empty?
          warn "Error: No connector found matching '#{title}'."
          warn "       Check the title and try again, or use --title with a different value."
          exit 1
        end

        if results.size > 1
          warn "Error: Multiple connectors matched '#{title}':"
          results.each { |r| warn "  - #{r['title']} (id: #{r['id']}, name: #{r['name']})" }
          warn "       Use --title with a more specific name."
          exit 1
        end

        results.first
      end

      def handle_http_error(status, context, identifier, body: nil)
        return if status == 200

        warn "Error: #{context} request failed for '#{identifier}' (HTTP #{status})."
        warn "       Response body: #{body}" unless body.nil? || body.strip.empty?
        exit 1
      end

      def save_logo(pull_dir, base64_logo)
        return nil if base64_logo.nil? || base64_logo.strip.empty?

        logo_file = File.join(pull_dir, LOGO_FILENAME)
        File.binwrite(logo_file, Base64.decode64(base64_logo))
        logo_file
      end

      def save_versions(pull_dir, connector)
        versions      = connector.select { |k, _| VERSION_KEYS.include?(k) }
        versions_file = File.join(pull_dir, 'versions.json')
        write_json(versions_file, versions)
        versions_file
      end

      def maybe_save_title(connector, config, config_path)
        stored = config.dig('connector', 'title')
        return unless stored.nil? || stored.strip.empty?

        api_title = connector['title']
        return unless api_title && !api_title.strip.empty?

        config['connector'] ||= {}
        config['connector']['title'] = api_title
        Wisco::Config.save_config(config_path, config)
      end

      def write_json(path, data)
        File.write(path, JSON.pretty_generate(data) + "\n")
      end
    end
  end
end
