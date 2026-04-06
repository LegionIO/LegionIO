# frozen_string_literal: true

require 'socket'
require 'concurrent/atomic/atomic_reference'
require 'concurrent/atomic/atomic_boolean'

module Legion
  module Identity
    module Process
      EMPTY_STATE = {
        id:             nil,
        canonical_name: nil,
        kind:           nil,
        persistent:     false
      }.freeze

      class << self
        def id
          state = @state.get
          state[:id] || Legion.instance_id
        end

        def canonical_name
          state = @state.get
          state[:canonical_name] || 'anonymous'
        end

        def kind
          @state.get[:kind]
        end

        def mode
          Legion::Mode.current
        end

        def queue_prefix
          name = canonical_name
          case mode
          when :agent
            "agent.#{name}.#{safe_hostname}"
          when :worker
            "worker.#{name}.#{Legion.instance_id}"
          when :infra
            "infra.#{name}.#{safe_hostname}"
          when :lite
            "lite.#{name}.#{Legion.instance_id}"
          else
            "agent.#{name}.#{safe_hostname}"
          end
        end

        def resolved?
          @resolved.true?
        end

        def persistent?
          @state.get[:persistent] == true
        end

        def identity_hash
          {
            id:             id,
            canonical_name: canonical_name,
            kind:           kind,
            mode:           mode,
            queue_prefix:   queue_prefix,
            resolved:       resolved?,
            persistent:     persistent?
          }
        end

        def bind!(provider, identity_hash)
          @provider = provider
          @state.set({
                       id:             identity_hash[:id],
                       canonical_name: identity_hash[:canonical_name],
                       kind:           identity_hash[:kind],
                       persistent:     identity_hash.fetch(:persistent, true)
                     })
          @resolved.make_true
        end

        def bind_fallback!
          user = ENV.fetch('USER', 'anonymous')
          @state.set({
                       id:             nil,
                       canonical_name: user,
                       kind:           :human,
                       persistent:     false
                     })
          @resolved.make_false
        end

        def refresh_credentials
          return unless defined?(@provider) && @provider.respond_to?(:refresh)

          @provider.refresh
        end

        def reset!
          @state    = Concurrent::AtomicReference.new(EMPTY_STATE.dup)
          @resolved = Concurrent::AtomicBoolean.new(false)
          @provider = nil
        end

        private

        def safe_hostname
          ::Socket.gethostname.downcase.gsub(/[^a-z0-9\-]/, '')
        end
      end

      # Initialize atomics at module definition time
      reset!
    end
  end
end
