# frozen_string_literal: true

require 'legion/logging'
Legion::Logging.setup(level: 'fatal', log_file: File::NULL, log_stdout: false, async: false)

# Failure injection is confined to dependency loading, never the auth facade.
module ChatgptMissingExtension
  private

  def require(path)
    raise LoadError, 'fixture-private-dependency-error' if path == 'legion/extensions/llm/openai'

    super
  end
end

if ENV['LEGION_CHATGPT_FIXTURE_MISSING'] == 'true'
  Kernel.prepend(ChatgptMissingExtension)
else
  require 'legion/extensions/llm/openai/chatgpt/oauth_http'

  # Keep the actual OAuth client and protocol; replace only its remote peer.
  module ChatgptLoopbackTransport
    private

    def build_connection(**)
      Net::HTTP.new('127.0.0.1', Integer(ENV.fetch('LEGION_CHATGPT_FIXTURE_PORT')), nil)
    end
  end

  Legion::Extensions::Llm::Openai::Chatgpt::OAuthHttp.prepend(ChatgptLoopbackTransport)
end
