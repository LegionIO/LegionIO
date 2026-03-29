# frozen_string_literal: true

require 'securerandom'

module Legion
  class API < Sinatra::Base
    module Routes
      module TbiPatterns
        # Defined at module level so it is accessible from both module methods
        # and the Helpers mixin without Sinatra constant-lookup context issues.
        ANON_FIELDS = %i[worker_id instance_id node_id].freeze
        MEMORY_MAX_SIZE = 500
        VALID_TIERS = (0..6).to_a.freeze

        # ---------------------------------------------------------------------------
        # Class-level store — lazy initialization avoids parse-time mutation and
        # prevents state bleed when the module is registered multiple times in tests.
        # ---------------------------------------------------------------------------
        class << self
          def memory_mutex
            @memory_mutex ||= Mutex.new
          end

          # Thread-safe read: returns a dup of the store.
          def memory_patterns
            memory_mutex.synchronize { (@memory_store ||= []).dup }
          end

          def persist_to_memory(pattern)
            memory_mutex.synchronize do
              @memory_store ||= []
              @memory_store.shift if @memory_store.size >= MEMORY_MAX_SIZE
              @memory_store << pattern
            end
          end

          # Strips identifying fields for anonymous cross-instance sharing.
          # Defined as a module method so it can be called from route blocks
          # without relying on Sinatra's instance `self` for constant resolution.
          def anonymize(pattern)
            pattern.reject { |k, _| ANON_FIELDS.include?(k.to_sym) }
          end

          # Validate the shape of an incoming export payload.
          def validate_payload_shape!(body)
            raise ArgumentError, 'payload must be a Hash' unless body.is_a?(Hash)
            if body.key?(:payload_shape) && !body[:payload_shape].is_a?(Hash)
              raise ArgumentError, 'payload_shape must be a Hash'
            end
          end

          # Server-side quality score — deliberately ignores caller-supplied
          # invocation_count / success_rate to satisfy issue requirement #5.
          def compute_quality_score(pattern)
            score = 50 # baseline
            score += 15 if pattern[:description].is_a?(String) && pattern[:description].length > 10
            score += 10 if pattern[:payload_shape].is_a?(Hash) && !pattern[:payload_shape].empty?
            score += 5  if VALID_TIERS.include?(pattern[:tier].to_i)

            # Augment from stored DB usage data when available.
            if defined?(Legion::Data::Model::TbiPattern) && pattern[:id]
              begin
                record = Legion::Data::Model::TbiPattern.first(id: pattern[:id].to_s)
                if record
                  stored_count = record.values[:invocation_count].to_i
                  stored_rate  = record.values[:success_rate].to_f
                  score += [stored_count / 100, 20].min
                  score += (stored_rate * 10).to_i
                end
              rescue StandardError
                nil
              end
            end

            [[score, 0].max, 100].min
          end

          # ---------------------------------------------------------------------------
          # Persistence helpers
          # ---------------------------------------------------------------------------
          def persist_pattern(pattern)
            if defined?(Legion::Data::Model::TbiPattern)
              begin
                # Use the UUID string as the primary key — do NOT call .to_i.
                record = Legion::Data::Model::TbiPattern.create(pattern)
                record.values
              rescue StandardError => e
                Legion::Logging.warn("TbiPatterns persist_pattern DB failed, using memory: #{e.message}") if defined?(Legion::Logging)
                persist_to_memory(pattern)
                pattern
              end
            else
              persist_to_memory(pattern)
              pattern
            end
          end

          def fetch_patterns(tier: nil)
            if defined?(Legion::Data::Model::TbiPattern)
              begin
                ds = Legion::Data::Model::TbiPattern.order(Sequel.desc(:exported_at))
                ds = ds.where(tier: tier.to_i) if tier
                return ds.all.map(&:values)
              rescue StandardError => e
                Legion::Logging.warn("TbiPatterns fetch_patterns DB failed, using memory: #{e.message}") if defined?(Legion::Logging)
              end
            end
            patterns = memory_patterns
            tier ? patterns.select { |p| p[:tier].to_i == tier.to_i } : patterns
          end

          def find_pattern(id)
            if defined?(Legion::Data::Model::TbiPattern)
              begin
                # Query by string UUID — no .to_i coercion.
                record = Legion::Data::Model::TbiPattern.first(id: id.to_s)
                return record.values if record
              rescue StandardError => e
                Legion::Logging.warn("TbiPatterns find_pattern DB failed, using memory: #{e.message}") if defined?(Legion::Logging)
              end
            end
            memory_patterns.find { |p| p[:id] == id }
          end

          # ---------------------------------------------------------------------------
          # Route registration helpers (private)
          # ---------------------------------------------------------------------------
          def register_export(app)
            app.post '/api/tbi/patterns/export' do
              content_type :json
              body = parse_request_body

              begin
                Legion::API::Routes::TbiPatterns.validate_payload_shape!(body)
              rescue ArgumentError => e
                content_type :json
                halt 422, Legion::JSON.dump({ error: { code: 'invalid_payload', message: e.message },
                                              meta: response_meta })
              end

              tier = body[:tier].to_i
              unless Legion::API::Routes::TbiPatterns::VALID_TIERS.include?(tier)
                content_type :json
                halt 422, Legion::JSON.dump({ error: { code: 'invalid_tier',
                                                        message: 'tier must be an integer 0-6' },
                                              meta: response_meta })
              end

              anon = Legion::API::Routes::TbiPatterns.anonymize(body)
              pattern = anon.merge(
                id:          SecureRandom.uuid,
                tier:        tier,
                exported_at: Time.now.utc.iso8601
              )

              saved = Legion::API::Routes::TbiPatterns.persist_pattern(pattern)
              json_response(saved, status_code: 201)
            rescue StandardError => e
              Legion::Logging.error "API POST /api/tbi/patterns/export: #{e.class} — #{e.message}" if defined?(Legion::Logging)
              json_error('export_error', e.message, status_code: 500)
            end
          end

          def register_import(app)
            app.get '/api/tbi/patterns' do
              content_type :json
              tier = params[:tier]
              patterns = Legion::API::Routes::TbiPatterns.fetch_patterns(tier: tier)
              json_response({ patterns: patterns, count: patterns.size })
            rescue StandardError => e
              Legion::Logging.error "API GET /api/tbi/patterns: #{e.class} — #{e.message}" if defined?(Legion::Logging)
              json_error('fetch_error', e.message, status_code: 500)
            end

            app.get '/api/tbi/patterns/:id' do
              content_type :json
              pattern = Legion::API::Routes::TbiPatterns.find_pattern(params[:id])
              if pattern.nil?
                content_type :json
                halt 404, Legion::JSON.dump({ error: { code: 'not_found',
                                                        message: "Pattern #{params[:id]} not found" },
                                              meta: response_meta })
              end
              json_response(pattern)
            rescue StandardError => e
              Legion::Logging.error "API GET /api/tbi/patterns/#{params[:id]}: #{e.class} — #{e.message}" if defined?(Legion::Logging)
              json_error('fetch_error', e.message, status_code: 500)
            end
          end

          def register_quality(app)
            # Quality score is computed server-side only — caller-supplied metrics are ignored.
            app.get '/api/tbi/patterns/:id/quality' do
              content_type :json
              pattern = Legion::API::Routes::TbiPatterns.find_pattern(params[:id])
              if pattern.nil?
                content_type :json
                halt 404, Legion::JSON.dump({ error: { code: 'not_found',
                                                        message: "Pattern #{params[:id]} not found" },
                                              meta: response_meta })
              end
              score = Legion::API::Routes::TbiPatterns.compute_quality_score(pattern)
              json_response({ id: params[:id], quality_score: score,
                              note: 'server-computed from stored data only; caller-supplied metrics are ignored' })
            rescue StandardError => e
              Legion::Logging.error "API GET /api/tbi/patterns/#{params[:id]}/quality: #{e.class} — #{e.message}" if defined?(Legion::Logging)
              json_error('quality_error', e.message, status_code: 500)
            end
          end

          # Cross-instance pattern discovery.
          # Implements the local-node side of federation. Peer instances are configured
          # via settings[:tbi][:marketplace][:peers] (Array of URLs).
          # TODO Phase 6: implement active peer pull once peer authentication is designed.
          def register_discovery(app)
            app.get '/api/tbi/patterns/discover' do
              content_type :json
              peers = []
              begin
                peers_cfg = Legion::Settings[:tbi]&.dig(:marketplace, :peers)
                peers = Array(peers_cfg).map(&:to_s) if peers_cfg
              rescue StandardError
                peers = []
              end

              local_name = begin
                             Legion::Settings[:client][:name]
                           rescue StandardError
                             'unknown'
                           end

              json_response({
                              local_instance:    local_name,
                              peers:             peers,
                              federation_status: peers.empty? ? 'unconfigured' : 'configured',
                              note:              'Configure tbi.marketplace.peers in settings to enable cross-instance discovery. ' \
                                                 'Active peer pull is a Phase 6 feature (not yet implemented).'
                            })
            rescue StandardError => e
              Legion::Logging.error "API GET /api/tbi/patterns/discover: #{e.class} — #{e.message}" if defined?(Legion::Logging)
              json_error('discovery_error', e.message, status_code: 500)
            end
          end

          private :register_export, :register_import, :register_quality, :register_discovery,
                  :persist_to_memory, :persist_pattern, :fetch_patterns, :find_pattern,
                  :validate_payload_shape!, :compute_quality_score, :anonymize, :memory_patterns
        end

        def self.registered(app)
          # Authentication guard on write endpoints.
          # Uses the same authenticate! helper available to other protected routes.
          # The global Legion::Rbac::Middleware also applies; this guard provides an
          # explicit layer in case RBAC middleware is not loaded.
          app.before '/api/tbi/patterns/export' do
            authenticate! if respond_to?(:authenticate!, true)
          end

          register_export(app)
          register_import(app)
          register_quality(app)
          register_discovery(app)
        end
      end
    end
  end
end
