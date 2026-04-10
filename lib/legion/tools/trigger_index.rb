# frozen_string_literal: true

module Legion
  module Tools
    module TriggerIndex
      @index = if defined?(Concurrent::Map)
                 Concurrent::Map.new
               else
                 {}
               end
      @mutex = Mutex.new unless defined?(Concurrent::Map)

      class << self
        def build_from_registry
          clear
          Registry.all_tools.each do |tool_class|
            words = Array(tool_class.trigger_words)
            next if words.empty?

            normalized = words.flat_map { |w| w.downcase.gsub(/[^a-z ]/, ' ').split }.uniq
            normalized.each { |word| add_tool_for_word(word, tool_class) }
          end
        end

        def build_async!
          if defined?(Concurrent::Promises)
            Concurrent::Promises.future { build_from_registry }
          else
            build_from_registry
          end
        end

        def match(word_set)
          matched = Set.new
          per_word = {}
          word_set.each do |word|
            normalized = word.to_s.downcase.gsub(/[^a-z ]/, ' ').strip
            next if normalized.empty?

            tools = read_word(normalized)
            next unless tools

            per_word[normalized] = tools
            matched.merge(tools)
          end
          [matched, per_word]
        end

        def empty?
          if defined?(Concurrent::Map) && @index.is_a?(Concurrent::Map)
            @index.each_pair.none?
          else
            @index.empty?
          end
        end

        def size
          if defined?(Concurrent::Map) && @index.is_a?(Concurrent::Map)
            count = 0
            @index.each_pair { count += 1 }
            count
          else
            @index.size
          end
        end

        def clear
          if defined?(Concurrent::Map) && @index.is_a?(Concurrent::Map)
            @index = Concurrent::Map.new
          else
            @mutex.synchronize { @index = {} }
          end
        end

        private

        def add_tool_for_word(word, tool_class)
          if defined?(Concurrent::Map) && @index.is_a?(Concurrent::Map)
            @index.compute(word) { |existing| ((existing || Set.new) + Set[tool_class]).freeze }
          else
            @mutex.synchronize do
              @index[word] ||= Set.new
              @index[word] = (@index[word] + Set[tool_class]).freeze
            end
          end
        end

        def read_word(word)
          if defined?(Concurrent::Map) && @index.is_a?(Concurrent::Map)
            @index[word]
          else
            @mutex&.synchronize { @index[word] }
          end
        end
      end
    end
  end
end
