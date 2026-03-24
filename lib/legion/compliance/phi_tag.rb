# frozen_string_literal: true

module Legion
  module Compliance
    module PhiTag
      class << self
        def phi?(metadata)
          return false unless Legion::Compliance.phi_enabled?
          return false unless metadata.is_a?(Hash)

          metadata[:phi] == true
        end

        def tag(metadata)
          base = metadata.is_a?(Hash) ? metadata : {}
          base.merge(phi: true, data_classification: 'restricted')
        end

        def tagged_cache_key(key)
          str = key.to_s
          return str if str.start_with?('phi:')

          "phi:#{str}"
        end
      end
    end
  end
end
