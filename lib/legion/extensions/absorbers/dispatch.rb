# frozen_string_literal: true

require 'securerandom'
require 'uri'
require_relative 'pattern_matcher'

module Legion
  module Extensions
    module Absorbers
      module Dispatch
        @dispatched = []
        @mutex = Mutex.new

        module_function

        def dispatch(input, context: {})
          context = default_context.merge(context)

          return { status: :depth_exceeded, input: input } if context[:depth] >= context[:max_depth]

          source_key = normalize_source_key(input)
          return { status: :cycle_detected, input: input } if context[:ancestor_chain]&.any? { |a| a.include?(source_key) }

          absorber_class = PatternMatcher.resolve(input)
          return nil unless absorber_class

          absorb_id = "absorb:#{SecureRandom.uuid}"

          record = {
            absorb_id:      absorb_id,
            input:          input,
            absorber_class: absorber_class.name,
            context:        context.merge(
              ancestor_chain: (context[:ancestor_chain] || []) + [absorb_id]
            ),
            status:         :dispatched,
            dispatched_at:  Time.now.utc.iso8601
          }

          publish_to_transport(absorber_class, input, record) if transport_available?

          @mutex.synchronize { @dispatched << record }
          record
        end

        def dispatch_children(children, parent_context:)
          children.map do |child|
            child_context = parent_context.merge(
              depth:            parent_context[:depth] + 1,
              parent_absorb_id: parent_context[:absorb_id]
            )
            dispatch(child[:url] || child[:file_path], context: child_context)
          end
        end

        def dispatched
          @mutex.synchronize { @dispatched.dup }
        end

        def reset_dispatched!
          @mutex.synchronize { @dispatched.clear }
        end

        def default_context
          {
            depth:            0,
            max_depth:        max_depth_setting,
            ancestor_chain:   [],
            conversation_id:  nil,
            requested_by:     nil,
            parent_absorb_id: nil
          }
        end

        def max_depth_setting
          return 5 unless defined?(Legion::Settings)

          Legion::Settings[:absorbers]&.dig(:max_depth) || 5
        end

        def normalize_source_key(input)
          input.to_s.gsub(%r{^https?://}, '').gsub(/[?#].*/, '')
        end

        def transport_available?
          defined?(Legion::Transport) &&
            Legion::Transport.respond_to?(:connected?) &&
            Legion::Transport.connected?
        end

        def publish_to_transport(absorber_class, _input, record)
          require_relative 'transport'
          Transport.publish_absorb_request(absorber_class: absorber_class, record: record)
        end

        def extract_urls(text)
          URI.extract(text, %w[http https]).uniq
        end
      end
    end
  end
end
