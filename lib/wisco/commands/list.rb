require_relative '../connector'

module Wisco
  module Commands
    module List
      TREE_FORK = '├── '
      TREE_LAST = '└── '
      TREE_PIPE = '│   '
      TREE_BLANK = '    '
      EXPANDABLE_KEYS = %i[actions triggers object_definitions methods pick_lists].freeze
      SORT_FIELDS = %w[key title].freeze

      module_function

      def run(subcommand, target, sort: nil, format: nil)
        validate_sort!(sort)

        if format
          run_formatted(target, format: format)
          return
        end

        case subcommand
        when nil        then run_tree(target)
        when 'actions'  then run_actions(target, sort: sort)
        when 'triggers' then run_triggers(target, sort: sort)
        when 'all'      then run_all(target, sort: sort)
        else
          warn "Error: Unknown list subcommand '#{subcommand}'"
          warn "Run '#{Wisco::CLI_NAME} --help' for usage."
          exit 1
        end
      end

      def run_tree(target_dir)
        connector = Wisco::Connector.load_connector_from_config(target_dir)
        puts connector[:title]

        keys = connector.keys
        keys.each_with_index do |key, idx|
          last = idx == keys.size - 1
          connector_str = last ? TREE_LAST : TREE_FORK
          child_prefix = last ? TREE_BLANK : TREE_PIPE
          value = connector[key]

          if key == :connection && value.is_a?(Hash)
            puts "#{connector_str}#{key}"
            render_connection_tree(value, child_prefix)
          elsif EXPANDABLE_KEYS.include?(key) && value.is_a?(Hash) && !value.empty?
            puts "#{connector_str}#{key} [#{value.size}]"
            render_children_tree(value, child_prefix)
          elsif value.is_a?(Hash)
            puts "#{connector_str}#{key} [#{value.size}]"
          elsif value.is_a?(Array)
            puts "#{connector_str}#{key} [#{value.size}]"
          else
            puts "#{connector_str}#{key}"
          end
        end
      end

      def run_actions(target_dir, sort: nil)
        connector = Wisco::Connector.load_connector_from_config(target_dir)
        actions = connector[:actions]

        if actions.nil? || actions.empty?
          puts 'No actions defined.'
          return
        end

        rows = actions.map { |key, item| [key, title_for(key, item), subtitle_for(item)] }
        rows = sort_rows(rows, sort)
        render_markdown_table(%w[Key Title Subtitle], rows)
      end

      def run_triggers(target_dir, sort: nil)
        connector = Wisco::Connector.load_connector_from_config(target_dir)
        triggers = connector[:triggers]

        if triggers.nil? || triggers.empty?
          puts 'No triggers defined.'
          return
        end

        rows = triggers.map { |key, item| [key, title_for(key, item), subtitle_for(item)] }
        rows = sort_rows(rows, sort)
        render_markdown_table(%w[Key Title Subtitle], rows)
      end

      def run_all(target_dir, sort: nil)
        puts '## Overview'
        run_tree(target_dir)
        puts
        puts '## Actions'
        run_actions(target_dir, sort: sort)
        puts
        puts '## Triggers'
        run_triggers(target_dir, sort: sort)
      end

      # ---------------------------------------------------------------------------
      # Machine-readable output
      # ---------------------------------------------------------------------------

      def run_formatted(target_dir, format:)
        require 'yaml' if format.downcase == 'yaml'
        connector = Wisco::Connector.load_connector_from_config(target_dir)
        data = build_connector_hash(connector)
        if format.downcase == 'yaml'
          puts data.to_yaml
        else
          puts JSON.pretty_generate(data)
        end
      end

      def build_connector_hash(connector)
        {
          'title'      => connector[:title].to_s,
          'connection' => build_connection(connector[:connection]),
          'actions'    => build_section(connector[:actions]),
          'triggers'   => build_section(connector[:triggers]),
          'methods'    => (connector[:methods]    || {}).keys.map(&:to_s).sort,
          'pick_lists' => (connector[:pick_lists] || {}).keys.map(&:to_s).sort
        }
      end

      def build_connection(conn)
        return { 'fields' => [] } unless conn.is_a?(Hash)

        fields = conn[:fields] || []
        { 'fields' => fields.map { |f| safe_serialize(f) }.compact }
      end

      def build_section(section)
        return {} unless section.is_a?(Hash)

        section.keys.sort_by(&:to_s).each_with_object({}) do |key, h|
          item = section[key]
          h[key.to_s] = {
            'title'    => title_for(key, item),
            'subtitle' => subtitle_for(item).to_s
          }
        end
      end

      # Recursively converts a connector value to a JSON-safe structure.
      # Proc/lambda values are dropped (returned as nil so callers can compact).
      def safe_serialize(value)
        case value
        when Hash
          value.each_with_object({}) do |(k, v), h|
            next if v.is_a?(Proc)

            serialized = safe_serialize(v)
            h[k.to_s] = serialized
          end
        when Array  then value.map { |v| safe_serialize(v) }
        when Proc   then nil
        when Symbol then value.to_s
        else             value
        end
      end

      # ---------------------------------------------------------------------------
      # List utilities
      # ---------------------------------------------------------------------------

      def strip_html(str)
        str.to_s.gsub(/<[^>]+>/, '').squeeze(' ').strip
      end

      def humanise_key(key)
        key.to_s.split('_').map(&:capitalize).join(' ')
      end

      def title_for(key, item)
        item.is_a?(Hash) && item[:title] ? item[:title] : humanise_key(key)
      end

      def subtitle_for(item)
        return '' unless item.is_a?(Hash)
        return item[:subtitle] if item[:subtitle]

        strip_html(item[:description]) if item[:description]
        item[:subtitle] || strip_html(item[:description].to_s)
      end

      def render_markdown_table(headers, rows)
        all_rows = [headers] + rows
        widths = headers.length.times.map do |i|
          all_rows.map { |r| r[i].to_s.length }.max
        end

        fmt = widths.map { |w| "%-#{w}s" }.join(' | ')
        sep = widths.map { |w| '-' * w }.join('-|-')

        puts "| #{format(fmt, *headers)} |"
        puts "|-#{sep}-|"
        rows.each { |r| puts "| #{format(fmt, *r)} |" }
      end

      def validate_sort!(sort)
        return if sort.nil? || SORT_FIELDS.include?(sort)

        warn "Error: Unsupported sort field '#{sort}'. Valid values: #{SORT_FIELDS.join(', ')}."
        exit 1
      end

      def sort_rows(rows, sort)
        return rows if sort.nil?

        index = SORT_FIELDS.index(sort)
        rows.sort_by { |row| [row[index].to_s.downcase, row[0].to_s.downcase] }
      end

      # ---------------------------------------------------------------------------
      # Tree rendering
      # ---------------------------------------------------------------------------

      def value_label(value)
        case value
        when Hash  then "[#{value.size}]"
        when Array then "[#{value.size}]"
        when Proc  then '(lambda)'
        else            value.to_s
        end
      end

      def render_connection_tree(conn, prefix)
        keys = conn.keys
        keys.each_with_index do |key, idx|
          last = idx == keys.size - 1
          connector = last ? TREE_LAST : TREE_FORK
          child_prefix = prefix + (last ? TREE_BLANK : TREE_PIPE)
          value = conn[key]

          if value.is_a?(Hash)
            puts "#{prefix}#{connector}#{key}"
            sub_keys = value.keys
            sub_keys.each_with_index do |sk, si|
              sl = si == sub_keys.size - 1
              sc = sl ? TREE_LAST : TREE_FORK
              puts "#{child_prefix}#{sc}#{sk}"
            end
          else
            puts "#{prefix}#{connector}#{key} #{value_label(value)}"
          end
        end
      end

      def render_children_tree(value, prefix)
        child_keys = value.keys.sort
        child_keys.each_with_index do |ck, ci|
          cl = ci == child_keys.size - 1
          puts "#{prefix}#{cl ? TREE_LAST : TREE_FORK}#{ck}"
        end
      end
    end
  end
end
