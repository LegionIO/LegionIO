# frozen_string_literal: true

require 'legion/cli/chat_command'

module Legion
  module CLI
    class Chat
      # Manages conversation context window size through deduplication,
      # stopword compression, and LLM-based summarization.
      # Integrates with Legion::LLM::Compressor when available.
      module ContextManager
        COMPACT_THRESHOLD = 40
        TOKEN_ESTIMATE_RATIO = 4 # ~4 chars per token

        class << self
          def compact(session, strategy: :auto)
            messages = session.chat.messages.map(&:to_h)
            return { compacted: false, reason: 'too_few_messages' } if messages.length < 4

            case strategy
            when :auto
              auto_compact(session, messages)
            when :dedup
              dedup_only(session, messages)
            when :summarize
              summarize_compact(session, messages)
            else
              { compacted: false, reason: 'unknown_strategy' }
            end
          end

          def should_auto_compact?(session)
            session.chat.messages.length >= COMPACT_THRESHOLD
          end

          def stats(session)
            messages = session.chat.messages.map(&:to_h)
            char_count = messages.sum { |m| m[:content].to_s.length }
            {
              message_count:    messages.length,
              estimated_tokens: char_count / TOKEN_ESTIMATE_RATIO,
              char_count:       char_count,
              by_role:          messages.group_by { |m| m[:role].to_s }.transform_values(&:size)
            }
          end

          private

          def auto_compact(session, messages)
            results = { strategy: :auto, steps: [] }

            dedup_result = try_dedup(messages)
            if dedup_result && dedup_result[:removed].positive?
              messages = dedup_result[:messages]
              results[:steps] << { action: :dedup, removed: dedup_result[:removed] }
            end

            if messages.length > COMPACT_THRESHOLD && compressor_available?
              compressed = compress_messages(messages)
              if compressed
                messages = compressed[:messages]
                results[:steps] << { action: :compress, method: :stopword }
              end
            end

            apply_messages(session, messages)
            results[:compacted] = results[:steps].any?
            results[:final_count] = messages.length
            results
          end

          def dedup_only(session, messages)
            dedup_result = try_dedup(messages)
            if dedup_result && dedup_result[:removed].positive?
              apply_messages(session, dedup_result[:messages])
              { compacted: true, strategy: :dedup, removed: dedup_result[:removed],
                final_count: dedup_result[:messages].length }
            else
              { compacted: false, reason: 'no_duplicates' }
            end
          end

          def summarize_compact(session, messages)
            if compressor_available?
              result = Legion::LLM::Compressor.summarize_messages(messages, max_tokens: 2000)
              if result[:compressed]
                session.chat.reset_messages!
                session.chat.add_message(role: :assistant, content: result[:summary])
                return { compacted: true, strategy: :summarize, method: result[:method] || :llm,
                         original_count: result[:original_count], final_count: 1 }
              end
            end

            { compacted: false, reason: 'summarization_unavailable' }
          end

          def try_dedup(messages)
            return nil unless compressor_available?

            Legion::LLM::Compressor.deduplicate_messages(messages, threshold: 0.85)
          rescue StandardError => e
            log_debug("dedup failed: #{e.message}")
            nil
          end

          def compress_messages(messages)
            compressed = messages.map do |msg|
              content = msg[:content].to_s
              next msg if content.length < 50

              compressed_content = Legion::LLM::Compressor.compress(content, level: 2)
              msg.merge(content: compressed_content)
            end
            { messages: compressed }
          rescue StandardError => e
            log_debug("compress failed: #{e.message}")
            nil
          end

          def apply_messages(session, messages)
            session.chat.reset_messages!
            messages.each { |msg| session.chat.add_message(msg) }
          end

          def compressor_available?
            defined?(Legion::LLM::Compressor)
          end

          def log_debug(msg)
            Legion::Logging.debug("ContextManager: #{msg}") if defined?(Legion::Logging)
          end
        end
      end
    end
  end
end
