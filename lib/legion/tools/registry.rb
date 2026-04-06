# frozen_string_literal: true

module Legion
  module Tools
    module Registry
      @always   = []
      @deferred = []
      @mutex    = Mutex.new

      class << self
        def register(tool_class)
          name = tool_class.tool_name
          is_deferred = tool_class.respond_to?(:deferred?) && tool_class.deferred?
          bucket = is_deferred ? :deferred : :always

          Legion::Logging.unknown "[Tools::Registry] register called: name=#{name} deferred=#{is_deferred} class=#{tool_class.name || tool_class.inspect}"

          @mutex.synchronize do
            target = bucket == :deferred ? @deferred : @always
            other  = bucket == :deferred ? @always : @deferred

            if target.any? { |t| t.tool_name == name } || other.any? { |t| t.tool_name == name }
              Legion::Logging.unknown "[Tools::Registry] DUPLICATE rejected: #{name}"
              return false
            end

            target << tool_class
            Legion::Logging.unknown "[Tools::Registry] registered: #{name} -> #{bucket} (always=#{@always.size} deferred=#{@deferred.size})"
            true
          end
        end

        def tools
          @mutex.synchronize { @always.dup }
        end

        def deferred_tools
          @mutex.synchronize { @deferred.dup }
        end

        def all_tools
          @mutex.synchronize { @always.dup + @deferred.dup }
        end

        def find(name)
          @mutex.synchronize do
            @always.find { |t| t.tool_name == name } ||
              @deferred.find { |t| t.tool_name == name }
          end
        end

        def always_loaded_names
          tools.map(&:tool_name)
        end

        # Catalog queries - replaces Catalog::Registry
        def for_extension(ext_name)
          all_tools.select { |t| t.respond_to?(:extension) && t.extension == ext_name }
        end

        def for_runner(runner_name)
          all_tools.select { |t| t.respond_to?(:runner) && t.runner == runner_name }
        end

        def tagged(tag)
          all_tools.select { |t| t.respond_to?(:tags) && t.tags.include?(tag) }
        end

        def clear
          Legion::Logging.unknown "[Tools::Registry] clear called (was: always=#{@always.size} deferred=#{@deferred.size})"
          @mutex.synchronize do
            @always.clear
            @deferred.clear
          end
        end
      end
    end
  end
end
