# frozen_string_literal: true

require 'securerandom'

module Legion
  module Context
    class SessionContext
      attr_reader :session_id, :user_id, :started_at, :metadata

      def initialize(session_id: nil, user_id: nil, metadata: {})
        @session_id = session_id || SecureRandom.uuid
        @user_id = user_id
        @started_at = Time.now
        @metadata = metadata
      end

      def to_h
        { session_id: session_id, user_id: user_id, started_at: started_at.iso8601 }
      end
    end

    class << self
      def current_session
        Thread.current[:legion_session_context]
      end

      def with_session(ctx)
        previous = Thread.current[:legion_session_context]
        Thread.current[:legion_session_context] = ctx
        yield
      ensure
        Thread.current[:legion_session_context] = previous
      end

      def session_metadata
        ctx = current_session
        return {} unless ctx

        ctx.to_h
      end

      def start_session(user_id: nil)
        ctx = SessionContext.new(user_id: user_id)
        Thread.current[:legion_session_context] = ctx
        Legion::Logging.debug "[Context] session started: #{ctx.session_id}" if defined?(Legion::Logging)
        ctx
      end

      def end_session
        ctx = Thread.current[:legion_session_context]
        Legion::Logging.debug "[Context] session cleared: #{ctx&.session_id}" if defined?(Legion::Logging)
        Thread.current[:legion_session_context] = nil
      end
    end
  end
end
