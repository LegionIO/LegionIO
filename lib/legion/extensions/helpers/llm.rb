# frozen_string_literal: true

module Legion
  module Extensions
    module Helpers
      module LLM
        # Quick embed from any extension runner, forwarding all keyword arguments.
        # Supports provider:, dimensions:, and any future parameters.
        # @param text [String, Array<String>] text to embed
        # @param kwargs [Hash] forwarded to Legion::LLM.embed (model:, provider:, dimensions:, etc.)
        # @return [Hash] embedding result with :vector, :dimensions, :model, :provider
        def llm_embed(text, **)
          Legion::LLM.embed(text, **)
        end
      end
    end
  end
end
