# frozen_string_literal: true

Process.setproctitle('Legion')
require 'concurrent'
require 'securerandom'
require 'legion/version'
require 'legion/logging'
require 'legion/events'
require 'legion/mode'
require 'legion/ingress'
require 'legion/process'
require 'legion/service'
require 'legion/extensions'
require 'legion/tools'

module Legion
  autoload :Region,  'legion/region'
  autoload :Lock,    'legion/lock'
  autoload :Leader,  'legion/leader'
  autoload :Prompts, 'legion/prompts'

  @instance_id = ENV.fetch('LEGIONIO_INSTANCE_ID') { SecureRandom.uuid }.downcase.strip.gsub(/[^a-z0-9\-]/, '')

  def self.instance_id
    @instance_id
  end

  attr_reader :service

  def self.start
    @service = Legion::Service.new
    Legion::Logging.info("Started Legion v#{Legion::VERSION}")
  end

  def self.shutdown
    @service.shutdown
  end

  def self.reload
    @service.reload
  end
end
