# frozen_string_literal: true

module Legion
  module Cluster
    class Leader
      HEARTBEAT_INTERVAL = 10 # seconds
      LOCK_NAME = 'legion_leader'

      attr_reader :node_id, :is_leader

      def initialize(node_id: SecureRandom.uuid)
        @node_id = node_id
        @is_leader = false
        @heartbeat_thread = nil
        @running = false
      end

      def start
        @running = true
        @heartbeat_thread = Thread.new { election_loop }
      end

      def stop
        @running = false
        @heartbeat_thread&.join(HEARTBEAT_INTERVAL + 2)
        resign if @is_leader
      end

      def leader?
        @is_leader
      end

      private

      def election_loop
        while @running
          attempt_election
          sleep(HEARTBEAT_INTERVAL)
        end
      end

      def attempt_election
        @is_leader = if Lock.acquire(name: LOCK_NAME)
                       true
                     else
                       false
                     end
      rescue StandardError => e
        Legion::Logging.warn "Leader#attempt_election failed: #{e.message}" if defined?(Legion::Logging)
        @is_leader = false
      end

      def resign
        Lock.release(name: LOCK_NAME) if @is_leader
        @is_leader = false
      end
    end
  end
end
