# frozen_string_literal: true

module Legion
  module Extensions
    class Handle
      STATES = %i[registered loaded starting running stopping stopped failed].freeze
      LOADED_STATES = %i[loaded starting running stopping].freeze
      DISPATCHABLE_STATES = %i[loaded starting running].freeze
      RELOAD_STATES = %i[idle pending updating rolling_back failed].freeze
      DISPATCH_BLOCKING_RELOAD_STATES = %i[updating rolling_back].freeze

      attr_reader :lex_name, :gem_name, :active_version, :state, :reload_state, :hot_reloadable,
                  :latest_installed_version, :spec, :gem_dir, :loaded_features, :actors, :routes, :tools, :absorbers,
                  :runners, :loaded_at, :last_error

      def initialize(**attrs)
        lex_name = attrs.fetch(:lex_name)
        spec = attrs[:spec]
        @lex_name = lex_name.to_s
        @gem_name = (attrs[:gem_name] || lex_name).to_s
        @spec = spec
        @active_version = normalize_version(attrs[:active_version] || spec&.version)
        @latest_installed_version = normalize_version(attrs[:latest_installed_version] || attrs[:installed_version] || @active_version)
        @state = normalize_state(attrs.fetch(:state, :registered))
        @reload_state = normalize_reload_state(attrs.fetch(:reload_state, :idle))
        @hot_reloadable = attrs[:hot_reloadable] == true
        @gem_dir = attrs[:gem_dir] || spec&.gem_dir
        @loaded_features = Array(attrs.fetch(:loaded_features, [])).dup.freeze
        @actors = Array(attrs.fetch(:actors, [])).dup.freeze
        @routes = Array(attrs.fetch(:routes, [])).dup.freeze
        @tools = Array(attrs.fetch(:tools, [])).dup.freeze
        @absorbers = Array(attrs.fetch(:absorbers, [])).dup.freeze
        @runners = Array(attrs.fetch(:runners, [])).dup.freeze
        @loaded_at = attrs.fetch(:loaded_at, Time.now)
        @last_error = attrs[:last_error]
      end

      def loaded?
        LOADED_STATES.include?(state)
      end

      def running?
        state == :running
      end

      def pending_reload?
        return false if active_version.nil? || latest_installed_version.nil?

        latest_installed_version > active_version
      end

      def dispatchable?
        DISPATCHABLE_STATES.include?(state) && !DISPATCH_BLOCKING_RELOAD_STATES.include?(reload_state)
      end

      def with(**attrs)
        self.class.new(**to_h, **attrs)
      end

      def to_h
        {
          lex_name:                 lex_name,
          gem_name:                 gem_name,
          active_version:           active_version,
          latest_installed_version: latest_installed_version,
          state:                    state,
          reload_state:             reload_state,
          hot_reloadable:           hot_reloadable,
          spec:                     spec,
          gem_dir:                  gem_dir,
          loaded_features:          loaded_features,
          actors:                   actors,
          routes:                   routes,
          tools:                    tools,
          absorbers:                absorbers,
          runners:                  runners,
          loaded_at:                loaded_at,
          last_error:               last_error
        }
      end

      private

      def normalize_version(value)
        return nil if value.nil?
        return value if value.is_a?(Gem::Version)

        Gem::Version.new(value.to_s)
      end

      def normalize_state(value)
        normalized = value.to_sym
        return normalized if STATES.include?(normalized)

        raise ArgumentError, "unknown extension state: #{value.inspect}"
      end

      def normalize_reload_state(value)
        normalized = value.to_sym
        return normalized if RELOAD_STATES.include?(normalized)

        raise ArgumentError, "unknown extension reload state: #{value.inspect}"
      end
    end
  end
end
