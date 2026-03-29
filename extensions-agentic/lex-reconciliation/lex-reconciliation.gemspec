# frozen_string_literal: true

require_relative 'lib/legion/extensions/reconciliation/version'

Gem::Specification.new do |spec|
  spec.name          = 'lex-reconciliation'
  spec.version       = Legion::Extensions::Reconciliation::VERSION
  spec.authors       = ['Esity']
  spec.email         = ['matthewdiverson@gmail.com']
  spec.summary       = 'A LegionIO Extension for drift detection and reconciliation'
  spec.description   = 'A LegionIO Extension (LEX) for detecting drift between expected and actual state and reconciling differences'
  spec.homepage      = 'https://github.com/LegionIO/lex-reconciliation'
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
