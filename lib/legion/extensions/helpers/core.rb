# frozen_string_literal: true

require_relative 'base'
module Legion
  module Extensions
    module Helpers
      module Core
        include Legion::Extensions::Helpers::Base

        def settings
          if Legion::Settings[:extensions].key?(lex_filename.to_sym)
            Legion::Settings[:extensions][lex_filename.to_sym]
          else
            { logger: { level: 'info', extended: false, internal: false } }
          end
        end

        # looks local, then in crypt, then settings, then cache, then env
        def find_setting(name, **opts)
          log.debug ".find_setting(#{name}) called"
          return opts[name.to_sym] if opts.key? name.to_sym

          string_name = "#{lex_name}_#{name.to_s.downcase}"
          if Legion::Settings[:crypt][:vault][:connected] && Legion::Crypt.exist?(lex_name)
            log.debug "looking for #{string_name} in Legion::Crypt"
            crypt_result = Legion::Crypt.get(lex_name)
            return crypt_result[name.to_sym] if crypt_result.is_a?(Hash) && crypt_result.key?(name.to_sym)
          end
          return settings[name.to_sym] if settings.key? name.to_sym

          if Legion::Settings[:cache][:connected]
            log.debug "looking for #{string_name} in Legion::Cache"
            cache_result = Legion::Cache.get(string_name)
            return cache_result unless cache_result.nil?
          end

          ENV[string_name] if ENV.key? string_name
          nil
        end
      end
    end
  end
end
