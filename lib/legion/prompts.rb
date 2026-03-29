# frozen_string_literal: true

module Legion
  module Prompts
    class << self
      def get(name, version: :production)
        client.get_prompt(name: name, tag: version.to_s)
      end

      def list
        client.list_prompts
      end

      private

      def client
        require 'legion/extensions/prompt/client'
        Legion::Extensions::Prompt::Client.new
      rescue LoadError => e
        raise LoadError, "lex-prompt is not installed: #{e.message}"
      end
    end
  end
end
