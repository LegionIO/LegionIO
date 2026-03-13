# frozen_string_literal: true

require 'legion/extensions/helpers/base'

module Legion
  module Extensions
    module Helpers
      module Cache
        include Legion::Extensions::Helpers::Base

        def cache_namespace
          @cache_namespace ||= lex_name
        end

        def cache_set(key, value, ttl: 60, **)
          Legion::Cache.set(cache_namespace + key, value, ttl: ttl)
        end

        def cache_get(key)
          Legion::Cache.get(cache_namespace + key)
        end
      end
    end
  end
end
