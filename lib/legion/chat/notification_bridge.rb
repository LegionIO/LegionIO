# frozen_string_literal: true

require_relative 'notification_queue'

module Legion
  module Chat
    class NotificationBridge
      DEFAULT_PATTERNS = {
        'alert.fired'                  => :critical,
        'extinction.*'                 => :critical,
        'governance.consent_violation' => :critical,
        'runner.failure'               => :info,
        'worker.lifecycle'             => :info,
        'scheduler.mode_changed'       => :info
      }.freeze

      attr_reader :queue

      def initialize(queue: NotificationQueue.new)
        @queue = queue
        @patterns = load_patterns
      end

      def start
        return unless defined?(Legion::Events)

        Legion::Events.on('*') do |event_name, payload|
          priority = match_priority(event_name)
          next unless priority

          message = format_notification(event_name, payload)
          @queue.push(message: message, priority: priority, source: event_name)
        end
      end

      def pending_notifications(max_priority: :info)
        @queue.pop_all(max_priority: max_priority)
      end

      def has_urgent? # rubocop:disable Naming/PredicatePrefix
        @queue.has_critical?
      end

      private

      def match_priority(event_name)
        @patterns.each do |pattern, priority|
          return priority if File.fnmatch?(pattern, event_name)
        end
        nil
      end

      def format_notification(event_name, payload)
        payload ||= {}
        case event_name
        when /\Aalert\./
          "[ALERT] #{payload[:rule] || event_name}: #{payload[:severity] || 'unknown'}"
        when /\Aextinction\./
          "[EXTINCTION] #{event_name} triggered"
        when /\Arunner\.failure/
          "[FAIL] #{payload[:extension]}.#{payload[:function]} failed"
        when /\Aworker\.lifecycle/
          "[WORKER] #{payload[:worker_id]} -> #{payload[:to]}"
        else
          "[#{event_name}]"
        end
      end

      def load_patterns
        custom = begin
          Legion::Settings.dig(:chat, :notifications, :patterns)
        rescue StandardError => e
          Legion::Logging.debug "NotificationBridge#load_patterns failed to read settings: #{e.message}" if defined?(Legion::Logging)
          nil
        end
        return DEFAULT_PATTERNS unless custom

        custom.to_h { |p| [p, :info] }
              .merge(DEFAULT_PATTERNS.select { |_, v| v == :critical })
      end
    end
  end
end
