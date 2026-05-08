# my_script.rb
require 'bundler/setup' # ensures only Gemfile gems are loaded
require 'thor'
require 'workato/connector/sdk'
require 'workato/cli/exec_command'

cmd = Workato::CLI::ExecCommand.new
