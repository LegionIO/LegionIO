# frozen_string_literal: true

require 'legion/extensions/helpers/base'

begin
  require 'legion/llm/helper'
rescue LoadError
  # legion-llm not available; LLM helper methods will be absent.
  # Extensions declaring llm_required? are skipped when the gem is missing.
end

module Legion
  module Extensions
    module Helpers
      module LLM
        include Legion::Extensions::Helpers::Base
        include Legion::LLM::Helper if defined?(Legion::LLM::Helper)
      end
    end
  end
end
