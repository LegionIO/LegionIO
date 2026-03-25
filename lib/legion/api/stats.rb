# frozen_string_literal: true

module Legion
  class API < Sinatra::Base
    module Routes
      module Stats
        def self.registered(app)
          app.get '/api/stats' do
            result = {}
            result[:extensions]  = Routes::Stats.collect_extensions
            result[:gaia]        = Routes::Stats.collect_gaia
            result[:transport]   = Routes::Stats.collect_transport
            result[:cache]       = Routes::Stats.collect_cache
            result[:cache_local] = Routes::Stats.collect_cache_local
            result[:llm]         = Routes::Stats.collect_llm
            result[:data]        = Routes::Stats.collect_data
            result[:data_local]  = Routes::Stats.collect_data_local
            result[:api]         = Routes::Stats.collect_api
            json_response(result)
          end
        end

        EXTENSION_IVARS = {
          loaded:       :@loaded_extensions,
          discovered:   :@extensions,
          subscription: :@subscription_tasks,
          every:        :@timer_tasks,
          poll:         :@poll_tasks,
          once:         :@once_tasks,
          loop:         :@loop_tasks,
          running:      :@running_instances
        }.freeze

        class << self
          def collect_extensions
            ext = Legion::Extensions
            EXTENSION_IVARS.transform_values { |ivar| ext.instance_variable_get(ivar)&.count || 0 }
          rescue StandardError => e
            { error: e.message }
          end

          def collect_gaia
            return { started: false } unless defined?(Legion::Gaia) && Legion::Gaia.respond_to?(:started?) && Legion::Gaia.started?

            Legion::Gaia.status
          rescue StandardError => e
            { error: e.message }
          end

          def collect_transport
            conn = Legion::Transport::Connection
            connected = begin
              Legion::Settings[:transport][:connected]
            rescue StandardError
              false
            end
            connector = defined?(Legion::Transport::TYPE) ? Legion::Transport::TYPE.to_s : 'unknown'

            info = { connected: connected, connector: connector }

            session = conn.session
            if session.respond_to?(:open?) && session.open?
              info[:session_open] = true
              info[:channel_max] = session.channel_max if session.respond_to?(:channel_max)
              # Bunny tracks open channels in @channels hash
              channels = session.instance_variable_get(:@channels)
              info[:channels_open] = channels.is_a?(Hash) ? channels.count : nil
            else
              info[:session_open] = false
            end

            info[:build_session_open] = conn.build_session_open?
            info[:lite_mode] = conn.lite_mode?
            info
          rescue StandardError => e
            { error: e.message }
          end

          def collect_cache
            return { connected: false } unless defined?(Legion::Cache)

            info = { connected: Legion::Cache.connected? }
            info[:using_local]  = Legion::Cache.using_local? if Legion::Cache.respond_to?(:using_local?)
            info[:using_memory] = Legion::Cache.instance_variable_get(:@using_memory) == true
            info[:driver] = begin
              Legion::Settings[:cache][:driver]
            rescue StandardError
              nil
            end

            if Legion::Cache.connected? && Legion::Cache.respond_to?(:size)
              info[:pool_size] = begin
                Legion::Cache.size
              rescue StandardError
                nil
              end
              info[:pool_available] = begin
                Legion::Cache.available
              rescue StandardError
                nil
              end
            end
            info
          rescue StandardError => e
            { error: e.message }
          end

          def collect_cache_local
            return { connected: false } unless defined?(Legion::Cache::Local)

            info = { connected: Legion::Cache::Local.connected? }
            if Legion::Cache::Local.connected?
              info[:pool_size] = begin
                Legion::Cache::Local.size
              rescue StandardError
                nil
              end
              info[:pool_available] = begin
                Legion::Cache::Local.available
              rescue StandardError
                nil
              end
            end
            info
          rescue StandardError => e
            { error: e.message }
          end

          def collect_llm
            return { started: false } unless defined?(Legion::LLM) && Legion::LLM.started?

            info = { started: true }
            s = Legion::LLM.settings
            info[:default_model]    = s[:default_model]
            info[:default_provider] = s[:default_provider]
            info[:pipeline_enabled] = s[:pipeline_enabled] == true

            if defined?(Legion::LLM::Router) && Legion::LLM::Router.routing_enabled?
              info[:routing_enabled] = true
              tracker = Legion::LLM::Router.health_tracker
              if tracker
                providers = s[:providers] || {}
                info[:provider_health] = providers.each_with_object({}) do |(name, _cfg), h|
                  h[name] = { circuit: tracker.circuit_state(name)&.to_s }
                rescue StandardError
                  nil
                end
              end
            else
              info[:routing_enabled] = false
            end

            if defined?(Legion::LLM::ConversationStore)
              store = Legion::LLM::ConversationStore
              info[:conversations] = store.respond_to?(:size) ? store.size : nil
            end
            info
          rescue StandardError => e
            { error: e.message }
          end

          def collect_data
            return { connected: false } unless defined?(Legion::Data) && Legion::Settings[:data][:connected]

            if Legion::Data.respond_to?(:stats)
              stats = Legion::Data.stats
              stats[:shared] || stats
            else
              { connected: true, adapter: begin
                Legion::Data::Connection.adapter
              rescue StandardError
                nil
              end }
            end
          rescue StandardError => e
            { error: e.message }
          end

          def collect_data_local
            return { connected: false } unless defined?(Legion::Data::Local) && Legion::Data::Local.connected?

            if Legion::Data::Local.respond_to?(:stats)
              Legion::Data::Local.stats
            else
              { connected: true }
            end
          rescue StandardError => e
            { error: e.message }
          end

          def collect_api
            port = Legion::Settings.dig(:api, :port) || Legion::Settings.dig(:http, :port) || 4567
            info = { port: port }

            # Puma thread pool stats if available
            puma_server = Puma::Server.current if defined?(Puma::Server) && Puma::Server.respond_to?(:current)
            if puma_server.respond_to?(:pool_capacity)
              info[:puma] = {
                pool_capacity: puma_server.pool_capacity,
                max_threads:   puma_server.max_threads,
                running:       puma_server.running,
                backlog:       puma_server.backlog
              }
            end

            info[:routes] = begin
              Legion::API.routes.values.flatten.count
            rescue StandardError
              nil
            end
            info
          rescue StandardError => e
            { error: e.message }
          end
        end
      end
    end
  end
end
