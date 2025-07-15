# frozen_string_literal: true

require_relative 'lib/yardmcp/version'

Gem::Specification.new do |spec|
  spec.name          = 'yardmcp'
  spec.version       = YardMCP::VERSION
  spec.authors       = 'Roman Shterenzon'
  spec.email         = 'roman.shterenzon@gmail.com'

  spec.summary       = 'Programmable server for Ruby gem/YARD documentation via FastMCP.'
  spec.description   = 'yardmcp exposes Ruby gem and YARD documentation as programmable tools via a FastMCP server.'
  spec.homepage      = 'https://github.com/romanbsd/yardmcp'
  spec.required_ruby_version = '>= 3.2'
  spec.license       = 'MIT'

  spec.files         = Dir['lib/**/*.rb'] + Dir['exe/*'] + ['README.md']
  spec.bindir        = 'exe'
  spec.executables   = ['yardmcp']
  spec.require_paths = ['lib']

  spec.add_dependency 'fast-mcp', '~> 1.5'
  spec.add_dependency 'levenshtein', '~> 0.2.2'
  spec.add_dependency 'yard', '~> 0.9.37'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
