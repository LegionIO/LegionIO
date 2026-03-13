# frozen_string_literal: true

module Legion
  module Supervision
    class << self
      attr_accessor :timer_tasks

      def setup
        @timer_tasks = Concurrent::AtomicReference.new([])
        @once_tasks = Concurrent::AtomicReference.new([])
        @loop_tasks = Concurrent::AtomicReference.new([])
        @poll_tasks = Concurrent::AtomicReference.new([])
        @subscriptions = Concurrent::AtomicReference.new([])
      end
    end
  end
end
