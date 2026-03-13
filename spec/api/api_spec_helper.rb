# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'legion/api'

module ApiSpecSetup
  def self.configure_settings
    Legion::Logging.setup(log_level: 'fatal', level: 'fatal', trace: false)
    Legion::Settings.load(config_dir: File.expand_path('..', __dir__))
    loader = Legion::Settings.loader
    loader.settings[:client] = { name: 'test-node', ready: true }
    loader.settings[:data] = { connected: false }
    loader.settings[:transport] = { connected: false }
    loader.settings[:extensions] = {}
  end
end
