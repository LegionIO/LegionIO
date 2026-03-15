# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'legion/version'

Gem::Specification.new do |spec|
  spec.name = 'legionio'
  spec.version       = Legion::VERSION
  spec.authors       = ['Esity']
  spec.email         = ['matthewdiverson@gmail.com']

  spec.summary       = 'The primary gem to run the LegionIO Framework'
  spec.description   = 'LegionIO is an extensible framework for running, scheduling and building relationships of tasks in a concurrent matter'
  spec.homepage      = 'https://github.com/LegionIO/LegionIO'
  spec.license       = 'Apache-2.0'
  spec.require_paths = ['lib']
  spec.required_ruby_version = '>= 3.4'

  spec.metadata = {
    'bug_tracker_uri'       => 'https://github.com/LegionIO/LegionIO/issues',
    'changelog_uri'         => 'https://github.com/LegionIO/LegionIO/blob/main/CHANGELOG.md',
    'documentation_uri'     => 'https://github.com/LegionIO/LegionIO',
    'homepage_uri'          => 'https://github.com/LegionIO/LegionIO',
    'source_code_uri'       => 'https://github.com/LegionIO/LegionIO',
    'wiki_uri'              => 'https://github.com/LegionIO/LegionIO',
    'rubygems_mfa_required' => 'true'
  }

  spec.files = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end

  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }

  spec.add_dependency 'mcp', '~> 0.8'

  spec.add_dependency 'concurrent-ruby', '>= 1.2'
  spec.add_dependency 'concurrent-ruby-ext', '>= 1.2'
  spec.add_dependency 'daemons', '>= 1.4'
  spec.add_dependency 'oj', '>= 3.16'
  spec.add_dependency 'puma', '>= 6.0'
  spec.add_dependency 'rackup', '>= 2.0'
  spec.add_dependency 'sinatra', '>= 4.0'
  spec.add_dependency 'rouge', '>= 4.0'
  spec.add_dependency 'thor', '>= 1.3'

  spec.add_dependency 'legion-cache', '>= 0.3'
  spec.add_dependency 'legion-crypt', '>= 0.3'
  spec.add_dependency 'legion-json', '>= 1.2'
  spec.add_dependency 'legion-logging', '>= 0.3'
  spec.add_dependency 'legion-settings', '>= 0.3'
  spec.add_dependency 'legion-transport', '>= 1.2'

  spec.add_dependency 'lex-node'
end
