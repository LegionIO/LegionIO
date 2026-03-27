# frozen_string_literal: true

require 'base64'
require 'net/http'
require 'uri'
require 'fileutils'
require 'json'

module Legion
  module CLI
    module ConfigImport
      SETTINGS_DIR = File.expand_path('~/.legionio/settings')
      BOOTSTRAPPED_FILE = 'bootstrapped_settings.json'

      SUBSYSTEM_KEYS = %i[
        microsoft_teams rbac api logging gaia extensions
        llm data cache_local cache transport crypt role
      ].freeze

      module_function

      def fetch_source(source)
        if source.match?(%r{\Ahttps?://})
          fetch_http(source)
        else
          raise CLI::Error, "File not found: #{source}" unless File.exist?(source)

          File.read(source)
        end
      end

      def fetch_http(url)
        uri = URI.parse(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 10
        http.read_timeout = 10
        request = Net::HTTP::Get.new(uri)
        response = http.request(request)
        raise CLI::Error, "HTTP #{response.code}: #{response.message}" unless response.is_a?(Net::HTTPSuccess)

        response.body
      end

      def parse_payload(body)
        parsed = ::JSON.parse(body, symbolize_names: true)
        raise CLI::Error, 'Config must be a JSON object' unless parsed.is_a?(Hash)

        parsed
      rescue ::JSON::ParserError
        begin
          decoded = Base64.decode64(body)
          parsed = ::JSON.parse(decoded, symbolize_names: true)
          raise CLI::Error, 'Config must be a JSON object' unless parsed.is_a?(Hash)

          parsed
        rescue ::JSON::ParserError
          raise CLI::Error, 'Source is not valid JSON or base64-encoded JSON'
        end
      end

      def write_config(config, force: false)
        FileUtils.mkdir_p(SETTINGS_DIR)
        written = []
        remainder = config.dup

        SUBSYSTEM_KEYS.each do |key|
          next unless remainder.key?(key)

          subsystem_data = remainder.delete(key)
          path = File.join(SETTINGS_DIR, "#{key}.json")
          File.write(path, "#{::JSON.pretty_generate({ key => subsystem_data })}\n")
          written << path
        end

        unless remainder.empty?
          path = File.join(SETTINGS_DIR, BOOTSTRAPPED_FILE)
          if File.exist?(path) && !force
            existing = ::JSON.parse(File.read(path), symbolize_names: true)
            remainder = deep_merge(existing, remainder)
          end
          File.write(path, "#{::JSON.pretty_generate(remainder)}\n")
          written << path
        end

        written
      end

      def deep_merge(base, overlay)
        base.merge(overlay) do |_key, old_val, new_val|
          if old_val.is_a?(Hash) && new_val.is_a?(Hash)
            deep_merge(old_val, new_val)
          else
            new_val
          end
        end
      end

      def summary(config)
        sections = config.keys.map(&:to_s)
        vault_clusters = config.dig(:crypt, :vault, :clusters)&.keys&.map(&:to_s) || []
        { sections: sections, vault_clusters: vault_clusters }
      end
    end
  end
end
