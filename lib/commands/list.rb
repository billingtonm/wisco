require_relative '../connector'

module Wisco
  module Commands
    module List
      TREE_FORK = '├── '
      TREE_LAST = '└── '
      TREE_PIPE = '│   '
      TREE_BLANK = '    '
      EXPANDABLE_KEYS = %i[actions triggers object_definitions methods pick_lists].freeze

      module_function

      def run(subcommand, target)
        case subcommand
        when nil        then run_tree(target)
        when 'actions'  then run_actions(target)
        when 'triggers' then run_triggers(target)
        when 'all'      then run_all(target)
        else
          warn "Error: Unknown list subcommand '#{subcommand}'"
          warn "Run '#{::CLI_NAME} --help' for usage."
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

      def run_actions(target_dir)
        connector = Wisco::Connector.load_connector_from_config(target_dir)
        actions = connector[:actions]

        if actions.nil? || actions.empty?
          puts 'No actions defined.'
          return
        end

        rows = actions.map { |key, item| [title_for(key, item), subtitle_for(item)] }
        render_markdown_table(%w[Title Subtitle], rows)
      end

      def run_triggers(target_dir)
        connector = Wisco::Connector.load_connector_from_config(target_dir)
        triggers = connector[:triggers]

        if triggers.nil? || triggers.empty?
          puts 'No triggers defined.'
          return
        end

        rows = triggers.map { |key, item| [title_for(key, item), subtitle_for(item)] }
        render_markdown_table(%w[Title Subtitle], rows)
      end

      def run_all(target_dir)
        puts '## Overview'
        run_tree(target_dir)
        puts
        puts '## Actions'
        run_actions(target_dir)
        puts
        puts '## Triggers'
        run_triggers(target_dir)
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
