# frozen_string_literal: true

require 'legion/extensions/handle'

module Legion
  module Extensions
    class HandleRegistry
      def initialize
        @handles = {}
        @mutex = Mutex.new
      end

      def register(lex_name, **attrs)
        key = normalize_name(lex_name)
        @mutex.synchronize do
          current = @handles[key]
          @handles[key] = current ? current.with(**attrs) : Handle.new(lex_name: key, **attrs)
        end
      end

      def transition(lex_name, state)
        update(lex_name, state: state)
      end

      def update(lex_name, **attrs)
        key = normalize_name(lex_name)
        @mutex.synchronize do
          current = @handles[key] || Handle.new(lex_name: key)
          @handles[key] = current.with(**attrs)
        end
      end

      def fetch(lex_name)
        @mutex.synchronize { @handles[normalize_name(lex_name)] }
      end

      def all
        @mutex.synchronize { @handles.values.dup }
      end

      def running
        all.select(&:running?)
      end

      def loaded
        all.select(&:loaded?)
      end

      def dispatch_allowed?(lex_name)
        handle = fetch(lex_name)
        return true unless handle

        handle.dispatchable?
      end

      def delete(lex_name)
        @mutex.synchronize { @handles.delete(normalize_name(lex_name)) }
      end

      def reset!
        @mutex.synchronize { @handles.clear }
      end

      private

      def normalize_name(lex_name)
        lex_name.to_s
      end
    end
  end
end
