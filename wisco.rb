$LOAD_PATH.unshift File.join(__dir__, 'lib')
require 'wisco'
Wisco::CLI.start(ARGV)
