module Wisco
  module PathUtils
    VALID_SECTIONS = %w[actions triggers].freeze

    module_function

    # Returns an array of [section, key] pairs derived from path_arg.
    #
    # Accepted forms:
    #   "section.key"  — one specific key in a known section
    #   "section"      — all keys in that section
    #   "key"          — auto-detect section; error if found in both or neither
    def parse_path(path_arg, connector)
      parts = path_arg.split('.', 2)

      if parts.size == 2
        section, key = parts
        unless VALID_SECTIONS.include?(section)
          warn "Error: Invalid section '#{section}'. Valid sections: #{VALID_SECTIONS.join(', ')}."
          exit 1
        end
        items = connector[section.to_sym]
        unless items&.key?(key.to_sym)
          warn "Error: '#{key}' not found in #{section}."
          exit 1
        end
        [[section, key]]

      elsif VALID_SECTIONS.include?(path_arg)
        section = path_arg
        items = connector[section.to_sym]
        if items.nil? || items.empty?
          warn "Error: No keys found in #{section}."
          exit 1
        end
        items.keys.map { |k| [section, k.to_s] }

      else
        key = path_arg
        in_actions  = connector[:actions]&.key?(key.to_sym)  || false
        in_triggers = connector[:triggers]&.key?(key.to_sym) || false

        case [in_actions, in_triggers]
        when [true, false]  then [['actions',  key]]
        when [false, true]  then [['triggers', key]]
        when [true, true]
          warn "Error: '#{key}' exists in both actions and triggers."
          warn "       Qualify with section, e.g. 'actions.#{key}'."
          exit 1
        else
          warn "Error: '#{key}' not found in actions or triggers."
          exit 1
        end
      end
    end
  end
end
