Process.setproctitle('Legion')
require 'concurrent'
require 'securerandom'
require 'legion/version'
require 'legion/events'
require 'legion/ingress'
require 'legion/process'
require 'legion/service'
require 'legion/extensions'

module Legion
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
