# frozen_string_literal: true

module Legion
  module Extensions
    module GemSource
      DEFAULT_SOURCE = 'https://rubygems.org'

      class << self
        def configured_sources
          raw = begin
            Legion::Settings.dig(:extensions, :sources)
          rescue StandardError
            nil
          end
          return [{ url: DEFAULT_SOURCE }] unless raw.is_a?(Array) && raw.any?

          raw.map { |s| s.is_a?(Hash) ? s : { url: s.to_s } }
        end

        def source_urls
          configured_sources.map { |s| s[:url] }.compact
        end

        def source_args_for_cli
          urls = source_urls
          return '' if urls.empty? || urls == [DEFAULT_SOURCE]

          "#{urls.map { |url| "--source #{url}" }.join(' ')} --clear-sources"
        end

        def install_gem(name, version: nil, gem_bin: nil)
          gem_bin ||= File.join(RbConfig::CONFIG['bindir'], 'gem')
          sources = source_args_for_cli
          version_arg = version ? "-v #{version}" : ''
          cmd = "#{gem_bin} install #{name} #{version_arg} --no-document #{sources}".strip.squeeze(' ')
          output = `#{cmd} 2>&1`
          { success: $CHILD_STATUS.success?, output: output, command: cmd }
        end

        def apply_credentials!
          configured_sources.each do |source|
            cred = source[:credentials] || source[:token]
            next unless cred

            url = source[:url]
            resolved = resolve_credential(cred)
            next unless resolved

            Gem.configuration.set_api_key(url, resolved)
          rescue StandardError => e
            Legion::Logging.debug "GemSource: credential setup failed for #{url}: #{e.message}" if defined?(Legion::Logging)
          end
        end

        def setup!
          apply_credentials!

          urls = source_urls
          return if urls.empty? || urls == [DEFAULT_SOURCE]

          urls.each do |url|
            Gem.sources << url unless Gem.sources.include?(url)
          end
        end

        private

        def resolve_credential(value)
          return value unless value.start_with?('env:')

          env_key = value.delete_prefix('env:')
          ENV.fetch(env_key, nil)
        end
      end
    end
  end
end
