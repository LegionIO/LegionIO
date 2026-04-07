# frozen_string_literal: true

module Legion
  module Mode
    LEGACY_MAP = { full: :agent, api: :worker, router: :worker, worker: :worker, lite: :lite }.freeze

    class << self
      def current
        raw = ENV['LEGION_MODE'] ||
              settings_dig(:mode) ||
              settings_dig(:process, :mode) ||
              legacy_role
        normalize(raw)
      end

      def agent?
        current == :agent
      end

      def worker?
        current == :worker
      end

      def infra?
        current == :infra
      end

      def lite?
        current == :lite
      end

      private

      def normalize(raw)
        return :agent if raw.nil?

        sym = raw.to_s.downcase.strip.to_sym
        return sym if %i[agent worker infra lite].include?(sym)

        LEGACY_MAP.fetch(sym, :agent)
      end

      def legacy_role
        settings_dig(:process, :role)
      end

      def fetch_setting_value(container, key)
        value = container[key]
        return value unless value.nil?

        alternate_key = case key
                        when Symbol then key.to_s
                        when String then key.to_sym
                        end
        return value if alternate_key.nil?

        container[alternate_key]
      end

      def settings_dig(*keys)
        return nil unless defined?(Legion::Settings) && Legion::Settings.respond_to?(:[])

        result = Legion::Settings
        keys.each do |k|
          return nil unless result.respond_to?(:[])

          result = fetch_setting_value(result, k)
          return nil if result.nil? && keys.last != k
        end
        result
      rescue StandardError
        nil
      end
    end
  end
end
