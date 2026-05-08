require_relative 'lib/wisco/version'

Gem::Specification.new do |spec|
  spec.name          = 'wisco'
  spec.version       = Wisco::VERSION
  spec.summary       = 'Workato Connector SDK Companion'
  spec.authors       = ['mbillington']
  spec.executables   = ['wisco']
  spec.files         = Dir['lib/**/*.rb']
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 2.7'

  spec.add_runtime_dependency 'activesupport', '~> 7.0.0'
  spec.add_runtime_dependency 'workato-connector-sdk', '1.3.19'
end
