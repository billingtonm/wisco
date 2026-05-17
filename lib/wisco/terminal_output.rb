module Wisco
  module TerminalOutput
    RED = 31
    YELLOW = 33

    module_function

    def emit_error(message)
      warn(colorize(message, RED))
    end

    def emit_warning(message)
      warn(colorize(message, YELLOW))
    end

    def colorize(message, color_code)
      return message unless $stderr.tty?

      "\e[#{color_code}m#{message}\e[0m"
    end
  end
end