# frozen_string_literal: true

require 'tsort'
require 'timeout'

module Legion
  class Provider
    class CyclicDependencyError < StandardError; end
    class MissingDependencyError < StandardError; end

    class << self
      def provides(name = nil)
        if name
          @provides = name.to_sym
          Registry.register(self)
        end
        @provides
      end

      def depends_on(*deps)
        if deps.any?
          @depends_on = deps.map(&:to_sym)
        else
          @depends_on || []
        end
      end

      def adapters(mapping = nil)
        if mapping
          @adapters = mapping
        else
          @adapters || {}
        end
      end
    end

    attr_reader :mode

    def initialize(mode: :full)
      @mode = mode
    end

    def select_adapter(mode)
      @mode = mode
      adapter_path = self.class.adapters[mode]
      require adapter_path if adapter_path
    end

    def boot
      raise NotImplementedError, "#{self.class}#boot must be implemented"
    end

    def shutdown
      # default no-op
    end

    def name
      self.class.provides
    end
  end

  class Provider
    module Registry
      class << self
        include TSort

        def providers
          @providers ||= {}
        end

        def register(provider_class)
          key = provider_class.provides
          return unless key

          providers[key] = provider_class
        end

        def boot_order
          validate_dependencies!
          tsort
        rescue TSort::Cyclic => e
          raise Provider::CyclicDependencyError, "cyclic dependency detected: #{e.message}"
        end

        def boot!(mode: :full, timeout: 30)
          booted = []
          boot_order.each do |key|
            klass = providers[key]
            instance = klass.new(mode: mode)
            instance.select_adapter(mode)

            Timeout.timeout(timeout) { instance.boot }
            Legion::Readiness.mark_ready(key) if defined?(Legion::Readiness)
            booted << instance
          rescue Timeout::Error => e
            Legion::Logging.error "Provider :#{key} boot timed out (#{timeout}s)" if defined?(Legion::Logging)
            shutdown!(booted)
            raise Provider::MissingDependencyError, "provider :#{key} timed out during boot: #{e.message}"
          rescue StandardError => e
            Legion::Logging.error "Provider :#{key} boot failed: #{e.message}" if defined?(Legion::Logging)
            shutdown!(booted)
            raise
          end
          booted
        end

        def shutdown!(instances)
          instances.reverse_each do |instance|
            instance.shutdown
            Legion::Readiness.mark_not_ready(instance.name) if defined?(Legion::Readiness)
          rescue StandardError => e
            Legion::Logging.warn "Provider shutdown error for #{instance.name}: #{e.message}" if defined?(Legion::Logging)
          end
        end

        def reset!
          @providers = {}
        end

        private

        def tsort_each_node(&)
          providers.each_key(&)
        end

        def tsort_each_child(node, &)
          klass = providers[node]
          return unless klass

          klass.depends_on.each(&)
        end

        def validate_dependencies!
          providers.each do |name, klass|
            klass.depends_on.each do |dep|
              next if providers.key?(dep)

              raise Provider::MissingDependencyError,
                    "provider :#{name} depends on :#{dep} which is not registered"
            end
          end
        end
      end
    end
  end
end
