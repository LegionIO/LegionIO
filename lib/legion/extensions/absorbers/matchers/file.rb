# frozen_string_literal: true

require_relative 'base'

module Legion
  module Extensions
    module Absorbers
      module Matchers
        class File < Base
          def self.match?(pattern, input)
            return false unless input.is_a?(::String)

            ::File.fnmatch(pattern, input, ::File::FNM_PATHNAME | ::File::FNM_DOTMATCH)
          end

          def self.type
            :file
          end
        end
      end
    end
  end
end
