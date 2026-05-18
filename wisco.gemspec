require_relative 'lib/wisco/version'

ROOT_DIR = __dir__

Gem::Specification.new do |spec|
  spec.name          = 'wisco'
  spec.version       = Wisco::VERSION
  spec.summary       = 'Workato Connector SDK Companion'
  spec.authors       = ['mbillington']
  spec.executables   = ['wisco']
  spec.files         = Dir.chdir(ROOT_DIR) { Dir['bin/*', 'lib/**/*.rb', "lib/**/{*,.*}"] }
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 2.7'

  spec.summary       = 'A CLI tool to assist with developing and managing Workato connectors.'
  spec.description     = <<~DESC
    Wisco is a command-line interface (CLI) tool designed to assist developers in creating and managing Workato connectors. 
    It extends the capabilities of the official Workato Connector SDK by providing additional features and streamlining common tasks, making the development process more efficient and user-friendly.
  DESC

  spec.license       = 'MIT'
  spec.homepage      = 'https://github.com/billingtonm/wisco'
  # spec.repository      = 'https://github.com/billingtonm/wisco'

  spec.add_runtime_dependency 'activesupport', '~> 7.0.0'
  spec.add_runtime_dependency 'workato-connector-sdk', '1.3.19'
  spec.add_runtime_dependency 'thor', '~> 1.0'
end
