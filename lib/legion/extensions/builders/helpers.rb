# frozen_string_literal: true

require_relative 'base'

module Legion
  module Extensions
    module Builder
      module Helpers
        include Legion::Extensions::Builder::Base

        def build_helpers
          @helpers ||= []
          @helpers.push(require_files(helper_files))
        end

        def helper_files
          @helper_files ||= find_files('helpers')
        end

        def helpers
          @helpers
        end
      end
    end
  end
end
