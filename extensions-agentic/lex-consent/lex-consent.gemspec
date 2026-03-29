# frozen_string_literal: true

require_relative 'lib/legion/extensions/agentic/consent/version'

Gem::Specification.new do |spec|
  spec.name          = 'lex-consent'
  spec.version       = Legion::Extensions::Agentic::Consent::VERSION
  spec.authors       = ['Esity']
  spec.email         = ['matthewdiverson@gmail.com']
  spec.summary       = 'LegionIO HITL consent gate for autonomous tier promotion'
  spec.description   = 'A LegionIO Extension (LEX) that gates agent autonomous tier promotion by human approval'
  spec.homepage      = 'https://github.com/LegionIO/lex-consent'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.4'

  spec.metadata = {
    'homepage_uri'          => spec.homepage,
    'source_code_uri'       => spec.homepage,
    'rubygems_mfa_required' => 'true'
  }

  spec.files = Dir['lib/**/*', 'LICENSE', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'legionio', '>= 1.2'
end
